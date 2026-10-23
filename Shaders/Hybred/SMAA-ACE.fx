/* SMAA-ACE for ReShade.

   ReShade port of the SMAA-ACE. The hybrid path
   writes edges to a full-resolution RG8 texture &and computes blend weights
   only for active edge pixels.

   Original SMAA algorithm, area texture and search texture by Jorge Jimenez,
   Jose I. Echevarria, Tiago Sousa and Diego Gutierrez. MIT license.

   Compute: D3D11, D3D12, OpenGL, Vulkan. Pixel: D3D9/D3D10 and other
   non-compute renderers.
*/

#ifndef SMAA_ACE_FX
#define SMAA_ACE_FX

// Configuration

// ReShade has no SM6 wave intrinsics; use groupshared atomic compaction.
#ifndef SMAA_GROUP_SIZE_X
#define SMAA_GROUP_SIZE_X 32
#endif
#ifndef SMAA_GROUP_SIZE_Y
#define SMAA_GROUP_SIZE_Y 8
#endif
#ifndef SMAA_BATCH_SIZE
#define SMAA_BATCH_SIZE 1
#endif
#define SMAA_TILE_HEIGHT (SMAA_GROUP_SIZE_Y * SMAA_BATCH_SIZE)
#define SMAA_ACTIVE_SLOTS (SMAA_GROUP_SIZE_X * SMAA_GROUP_SIZE_Y * SMAA_BATCH_SIZE)

#define SMAA_AREATEX_MAX_DISTANCE 16
#define SMAA_AREATEX_MAX_DISTANCE_DIAG 20
#define SMAA_AREATEX_PIXEL_SIZE (1.0 / float2(160.0, 560.0))
#define SMAA_AREATEX_SUBTEX_SIZE (1.0 / 7.0)
#define SMAA_SEARCHTEX_SIZE float2(66.0, 33.0)
#define SMAA_SEARCHTEX_PACKED_SIZE float2(64.0, 16.0)
#define SMAA_LOCAL_CONTRAST_ADAPTATION_FACTOR 2.0

#define SMAA_LOW_CONTRAST_ADAPTIVE_THRESHOLD 1
#define SMAA_LOW_CONTRAST_CMAA_LCA 4
#define SMAA_LOW_CONTRAST_CMAA_SYNERGY 8

// D3D9 and D3D10 have no compute support in ReShade.
#if __RENDERER__ >= 0xb000
#define SMAA_COMPUTE_SUPPORTED 1
#else
#define SMAA_COMPUTE_SUPPORTED 0
#endif

// sRGB views only for 8-bit sRGB swap chains; HDR keeps its native encoding.
#if (BUFFER_COLOR_SPACE == 1) && (BUFFER_COLOR_BIT_DEPTH <= 8)
#define SMAA_SRGB_INPUT 1
#define SMAA_SRGB_OUTPUT 1
#else
#define SMAA_SRGB_INPUT 0
#define SMAA_SRGB_OUTPUT 0
#endif

// User parameters

uniform float SMAAEdgeThreshold <
    ui_type = "slider";
    ui_min = 0.001;
    ui_max = 1.0;
    ui_step = 0.001;
    ui_label = "Edge Threshold";
    ui_tooltip = "Color difference required to mark a pixel as an edge.";
    ui_category = "SMAA-ACE";
> = 0.100;

uniform int SMAAMaxSearchSteps <
    ui_type = "slider";
    ui_min = 1;
    ui_max = 112;
    ui_step = 1;
    ui_label = "Max Search Steps";
    ui_tooltip = "Maximum horizontal/vertical search distance in pixels.";
    ui_category = "SMAA-ACE";
> = 32;

uniform int SMAAMaxDiagonalSteps <
    ui_type = "slider";
    ui_min = 1;
    ui_max = 64;
    ui_step = 1;
    ui_label = "Max Diagonal Steps";
    ui_tooltip = "Maximum diagonal search distance in pixels.";
    ui_category = "SMAA-ACE";
> = 16;

uniform float SMAACornerRounding <
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 100.0;
    ui_step = 1.0;
    ui_label = "Corner Rounding";
    ui_tooltip = "Corner rounding percentage. The SMAA default is 25.";
    ui_category = "SMAA-ACE";
> = 25.0;

uniform int SMAAEdgeMode <
    ui_type = "combo";
    ui_items = "Max Channel\0Luma Weighted\0";
    ui_label = "Edge Detection Metric";
    ui_category = "SMAA-ACE";
> = 0;

uniform bool SMAAEnableLowContrast <
    ui_label = "Low-Contrast Edges";
    ui_tooltip = "Use the adaptive low-contrast edge detector. Costs roughly 40-55% more in the edge pass.";
    ui_category = "SMAA-ACE";
> = false;

uniform bool SMAALowContrastCMAA <
    ui_label = "CMAA Local Contrast";
    ui_tooltip = "Suppress edges that are not locally significant. Only used when low-contrast edges are enabled.";
    ui_category = "SMAA-ACE";
> = true;

uniform bool SMAALowContrastSynergy <
    ui_label = "CMAA/SMAA Synergy";
    ui_tooltip = "Combine CMAA local contrast with SMAA's local contrast adaptation. Only used with low-contrast edges.";
    ui_category = "SMAA-ACE";
> = true;

uniform float SMAALowContrastDark <
    ui_type = "slider";
    ui_min = 0.001;
    ui_max = 0.5;
    ui_step = 0.001;
    ui_label = "Low-Contrast Threshold (Dark)";
    ui_category = "SMAA-ACE";
> = 0.030;

uniform float SMAALowContrastBright <
    ui_type = "slider";
    ui_min = 0.001;
    ui_max = 0.5;
    ui_step = 0.001;
    ui_label = "Low-Contrast Threshold (Bright)";
    ui_category = "SMAA-ACE";
> = 0.095;

uniform float SMAALowContrastFloor <
    ui_type = "slider";
    ui_min = 0.001;
    ui_max = 0.5;
    ui_step = 0.001;
    ui_label = "Low-Contrast Threshold Floor";
    ui_category = "SMAA-ACE";
> = 0.035;

uniform float SMAALowContrastSynergyStrength <
    ui_type = "slider";
    ui_min = -1.0;
    ui_max = 1.0;
    ui_step = 0.01;
    ui_label = "Synergy Strength";
    ui_category = "SMAA-ACE";
> = -0.45;

uniform int SMAADebugMode <
    ui_type = "combo";
    ui_items = "Off\0Edges\0Blend Weights\0";
    ui_label = "Debug View";
    ui_category = "SMAA-ACE";
> = 0;

// Runtime parameter views

float4 SMAASearchParams()
{
    return float4(SMAAEdgeThreshold,
                  float(SMAAMaxSearchSteps),
                  float(SMAAMaxDiagonalSteps),
                  SMAACornerRounding);
}

float4 SMAALowContrastParams()
{
    return float4(SMAALowContrastDark,
                  SMAALowContrastBright,
                  SMAALowContrastFloor,
                  SMAALowContrastSynergyStrength);
}

int4 SMAAOptions()
{
    int lowContrast = 0;
    if (SMAAEnableLowContrast)
    {
        lowContrast |= SMAA_LOW_CONTRAST_ADAPTIVE_THRESHOLD;
        if (SMAALowContrastCMAA)
            lowContrast |= SMAA_LOW_CONTRAST_CMAA_LCA;
        if (SMAALowContrastSynergy)
            lowContrast |= SMAA_LOW_CONTRAST_CMAA_SYNERGY;
    }

    return int4(SMAAEdgeMode, SMAADebugMode, lowContrast, 0);
}

#define SearchParams SMAASearchParams()
#define LowContrastParams SMAALowContrastParams()
#define Options SMAAOptions()

static const float4 ScreenParams = float4(BUFFER_WIDTH, BUFFER_HEIGHT, BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

// Resources

texture2D ColorTex : COLOR;

texture2D AreaLUT <
    source = "AreaTex.dds";
> {
    Width = 160;
    Height = 560;
    Format = RGBA8;
    MipLevels = 1;
};

texture2D SearchLUT <
    source = "SearchTex.dds";
> {
    Width = 64;
    Height = 16;
    Format = R8;
    MipLevels = 1;
};

// Pixel-path edge buffer.
texture2D EdgesTex
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RG8;
    MipLevels = 1;
};

texture2D BlendTex
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
    MipLevels = 1;
};

sampler2D ColorGammaSampler
{
    Texture = ColorTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = POINT;
    MinFilter = POINT;
    MipFilter = POINT;
    SRGBTexture = false;
};

sampler2D ColorLinearSampler
{
    Texture = ColorTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
    SRGBTexture = SMAA_SRGB_INPUT;
};

sampler2D EdgesSampler
{
    Texture = EdgesTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = POINT;
    SRGBTexture = false;
};

sampler2D BlendSampler
{
    Texture = BlendTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = POINT;
    MinFilter = POINT;
    MipFilter = POINT;
    SRGBTexture = false;
};

sampler2D AreaSampler
{
    Texture = AreaLUT;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = POINT;
    SRGBTexture = false;
};

sampler2D SearchSampler
{
    Texture = SearchLUT;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = POINT;
    SRGBTexture = false;
};

#if SMAA_COMPUTE_SUPPORTED

storage2D BlendTexStorage
{
    Texture = BlendTex;
    MipLevel = 0;
};

#endif

// Common helpers

void SMAAMovc(bool2 cond, inout float2 variable, float2 value)
{
    variable = cond ? value : variable;
}

void SMAAMovc(bool4 cond, inout float4 variable, float4 value)
{
    variable = cond ? value : variable;
}

float3 SMAALoadColor(int2 pixel)
{
    int2 size = int2(ScreenParams.xy);
    return tex2Dfetch(ColorGammaSampler, clamp(pixel, int2(0, 0), size - 1)).rgb;
}

float2 SMAALoadEdges(int2 pixel)
{
    int2 size = int2(ScreenParams.xy);
    pixel = clamp(pixel, int2(0, 0), size - 1);
    return tex2Dfetch(EdgesSampler, pixel).rg;
}

float2 SMAASampleEdges(float2 texcoord)
{
    return tex2Dlod(EdgesSampler, float4(texcoord, 0.0, 0.0)).rg;
}

float2 SMAASampleEdgesPoint(float2 texcoord)
{
    // Corner taps land on exact pixel centers; a point fetch avoids filtering.
    int2 pixel = int2(texcoord * ScreenParams.xy);
    return SMAALoadEdges(pixel);
}

void SMAABlendingWeightCalculationOffsets(float2 texcoord, out float4 offset[3])
{
    float2 pixelSize = ScreenParams.zw;

    offset[0] = mad(pixelSize.xyxy, float4(-0.25, -0.125, 1.25, -0.125), texcoord.xyxy);
    offset[1] = mad(pixelSize.xyxy, float4(-0.125, -0.25, -0.125, 1.25), texcoord.xyxy);
    offset[2] = mad(pixelSize.xxyy,
                    float4(-2.0, 2.0, -2.0, 2.0) * SearchParams.y,
                    float4(offset[0].xz, offset[1].yw));
}

float SMAACornerRoundingNorm()
{
    return SearchParams.w / 100.0;
}

// Edge detection

float SMAAMetric(float3 a, float3 b)
{
    float3 t = abs(a - b);
    float maxChannel = max(max(t.r, t.g), t.b);

    [branch]
    if (SMAAEdgeMode == 1)
    {
        return dot(t, float3(0.229, 0.587, 0.114) * 1.33);
    }

    return maxChannel;
}

float2 SMAAColorEdgeDetectionLowContrastCore(int2 pixel, out bool hasEdges)
{
    hasEdges = false;
    int2 size = int2(ScreenParams.xy);
    int2 p = clamp(pixel, int2(0, 0), size - 1);
    int2 lo = int2(0, 0);
    int2 hi = size - 1;

    float3 cC = SMAALoadColor(p);
    float3 maxColor = cC;

    float3 cW = SMAALoadColor(clamp(p + int2(-1, 0), lo, hi));
    maxColor = max(maxColor, cW);
    float dLeft = SMAAMetric(cC, cW);

    float3 cN = SMAALoadColor(clamp(p + int2(0, -1), lo, hi));
    maxColor = max(maxColor, cN);
    float dTop = SMAAMetric(cC, cN);

    float3 cE = SMAALoadColor(clamp(p + int2(1, 0), lo, hi));
    maxColor = max(maxColor, cE);
    float dRight = SMAAMetric(cC, cE);

    float3 cS = SMAALoadColor(clamp(p + int2(0, 1), lo, hi));
    maxColor = max(maxColor, cS);
    float dBottom = SMAAMetric(cC, cS);

    float2 cmaa = float2(0.0, 0.0);
    if ((Options.z & SMAA_LOW_CONTRAST_CMAA_LCA) != 0)
    {
        float3 cNW = SMAALoadColor(clamp(p + int2(-1, -1), lo, hi));
        maxColor = max(maxColor, cNW);
        float3 cNE = SMAALoadColor(clamp(p + int2(1, -1), lo, hi));
        maxColor = max(maxColor, cNE);
        float3 cSW = SMAALoadColor(clamp(p + int2(-1, 1), lo, hi));
        maxColor = max(maxColor, cSW);
        float3 cSE = SMAALoadColor(clamp(p + int2(1, 1), lo, hi));
        maxColor = max(maxColor, cSE);

        float dLeftN = SMAAMetric(cN, cNW);
        float dLeftNE = SMAAMetric(cNE, cN);
        float dTopS = SMAAMetric(cS, cC);
        float dTopW = SMAAMetric(cW, cNW);
        float dTopSW = SMAAMetric(cSW, cW);
        float dLeftE = SMAAMetric(cE, cC);

        float localLuma = saturate(max(maxColor.r * 0.297, max(maxColor.g, maxColor.b * 0.101)));
        float cmaaFactor = lerp(0.22, 0.15, localLuma);
        cmaa.x = max(max(dLeftN, dLeftNE), max(dLeft, dTopS)) * cmaaFactor;
        cmaa.y = max(max(dTopW, dTop), max(dTopSW, dLeftE)) * cmaaFactor;
    }

    float localLuma = saturate(max(maxColor.r * 0.297, max(maxColor.g, maxColor.b * 0.101)));

    float threshold = SearchParams.x;
    if ((Options.z & SMAA_LOW_CONTRAST_ADAPTIVE_THRESHOLD) != 0)
    {
        threshold = max(lerp(LowContrastParams.x, LowContrastParams.y, localLuma), LowContrastParams.z);
    }

    float2 centerDeltas = float2(dLeft, dTop) - cmaa;
    float2 edges = step(float2(threshold, threshold), centerDeltas);
    hasEdges = (edges.x + edges.y) > 0.0;

    if (!hasEdges)
    {
        return float2(0.0, 0.0);
    }

    float3 cWW = SMAALoadColor(clamp(p + int2(-2, 0), lo, hi));
    float3 cNN = SMAALoadColor(clamp(p + int2(0, -2), lo, hi));
    float dLeftLeft = SMAAMetric(cW, cWW);
    float dTopTop = SMAAMetric(cN, cNN);

    float finalDelta = max(max(max(dLeft, dTop), max(dRight, dBottom)),
                           max(dLeftLeft, dTopTop));

    float2 lcaDeltas = float2(dLeft, dTop);
    if ((Options.z & SMAA_LOW_CONTRAST_CMAA_SYNERGY) != 0)
    {
        lcaDeltas += cmaa * LowContrastParams.w;
    }

    edges *= step(finalDelta, SMAA_LOCAL_CONTRAST_ADAPTATION_FACTOR * lcaDeltas);
    return edges;
}

float2 SMAAColorEdgeDetectionCore(int2 pixel, out bool hasEdges)
{
    hasEdges = false;
    const float threshold = SearchParams.x;
    int2 size = int2(ScreenParams.xy);
    int2 p = clamp(pixel, int2(0, 0), size - 1);

    float4 delta;
    float3 c = SMAALoadColor(p);

    float3 cLeft = SMAALoadColor(p + int2(-1, 0));
    delta.x = SMAAMetric(c, cLeft);

    float3 cTop = SMAALoadColor(p + int2(0, -1));
    delta.y = SMAAMetric(c, cTop);

    float2 edges = step(float2(threshold, threshold), delta.xy);
    hasEdges = (edges.x + edges.y) > 0.0;

    if (!hasEdges)
    {
        return float2(0.0, 0.0);
    }

    float3 cRight = SMAALoadColor(p + int2(1, 0));
    delta.z = SMAAMetric(c, cRight);

    float3 cBottom = SMAALoadColor(p + int2(0, 1));
    delta.w = SMAAMetric(c, cBottom);

    float2 maxDelta = max(delta.xy, delta.zw);

    float3 cLeftLeft = SMAALoadColor(p + int2(-2, 0));
    delta.z = SMAAMetric(c, cLeftLeft);

    float3 cTopTop = SMAALoadColor(p + int2(0, -2));
    delta.w = SMAAMetric(c, cTopTop);

    maxDelta = max(maxDelta.xy, delta.zw);

    float finalDelta = max(maxDelta.x, maxDelta.y);
    edges.xy *= step(finalDelta, SMAA_LOCAL_CONTRAST_ADAPTATION_FACTOR * delta.xy);

    return edges;
}

// Edge and area decoding

float2 SMAADecodeDiagBilinearAccess(float2 e)
{
    e.r = e.r * abs(5.0 * e.r - 5.0 * 0.75);
    return round(e);
}

float4 SMAADecodeDiagBilinearAccess(float4 e)
{
    e.rb = e.rb * abs(5.0 * e.rb - 5.0 * 0.75);
    return round(e);
}

float2 SMAASearchDiag1(float2 pixcoord, int2 dir, out float2 e)
{
    int steps = -1;
    float last = 1.0;
    int2 p = int2(pixcoord);
    int maxSteps = int(SearchParams.z);
    e = float2(0.0, 0.0);

    while (steps < maxSteps - 1 && last > 0.9)
    {
        p += dir;
        steps += 1;
        e = SMAALoadEdges(p);
        last = dot(e, 0.5);
    }

    return float2(float(steps), last);
}

float2 SMAASearchDiag2(float2 texcoord, float2 dir, out float2 e)
{
    float4 coord = float4(texcoord, -1.0, 1.0);
    coord.x += 0.25 * ScreenParams.z;

    float3 t = float3(ScreenParams.zw, 1.0);
    float maxSteps = SearchParams.z;

    while (coord.z < maxSteps - 1.0 && coord.w > 0.9)
    {
        coord.xyz = mad(t, float3(dir, 1.0), coord.xyz);
        e = SMAASampleEdges(coord.xy);
        e = SMAADecodeDiagBilinearAccess(e);
        coord.w = dot(e, 0.5);
    }

    return coord.zw;
}

float2 SMAAAreaSample(float2 texcoord)
{
    return tex2Dlod(AreaSampler, float4(texcoord, 0.0, 0.0)).rg;
}

float2 SMAAAreaDiag(float2 dist, float2 e, float offset)
{
    float2 texcoord = mad(float2(SMAA_AREATEX_MAX_DISTANCE_DIAG, SMAA_AREATEX_MAX_DISTANCE_DIAG), e, dist);
    texcoord = mad(SMAA_AREATEX_PIXEL_SIZE, texcoord, 0.5 * SMAA_AREATEX_PIXEL_SIZE);
    texcoord.x += 0.5;
    texcoord.y += SMAA_AREATEX_SUBTEX_SIZE * offset;

    return SMAAAreaSample(texcoord);
}

float2 SMAACalculateDiagWeights(float2 texcoord,
                                float2 pixcoord,
                                float2 e,
                                float4 subsampleIndices)
{
    float2 weights = float2(0.0, 0.0);
    float2 pixelSize = ScreenParams.zw;

    float4 d;
    float2 end;

    if (e.r > 0.0)
    {
        d.xz = SMAASearchDiag1(pixcoord, int2(-1, 1), end);
        d.x += float(end.y > 0.9);
    }
    else
    {
        d.xz = 0.0;
    }

    d.yw = SMAASearchDiag1(pixcoord, int2(1, -1), end);

    [branch]
    if (d.x + d.y > 2.0)
    {
        float4 coords = mad(float4(-d.x + 0.25, d.x, d.y, -d.y - 0.25),
                            pixelSize.xyxy,
                            texcoord.xyxy);

        float4 c;
        c.xy = SMAASampleEdges(coords.xy + int2(-1, 0) * pixelSize);
        c.zw = SMAASampleEdges(coords.zw + int2(1, 0) * pixelSize);
        c.yxwz = SMAADecodeDiagBilinearAccess(c.xyzw);

        float2 cc = mad(float2(2.0, 2.0), c.xz, c.yw);
        SMAAMovc(bool2(step(0.9, d.zw)), cc, float2(0.0, 0.0));

        weights += SMAAAreaDiag(d.xy, cc, subsampleIndices.z);
    }

    d.xz = SMAASearchDiag2(texcoord, float2(-1.0, -1.0), end);

    int2 sidePixel = clamp(int2(pixcoord) + int2(1, 0), int2(0, 0), int2(ScreenParams.xy) - 1);
    if (SMAALoadEdges(sidePixel).r > 0.0)
    {
        d.yw = SMAASearchDiag2(texcoord, float2(1.0, 1.0), end);
        d.y += float(end.y > 0.9);
    }
    else
    {
        d.yw = 0.0;
    }

    [branch]
    if (d.x + d.y > 2.0)
    {
        float4 coords = mad(float4(-d.x, -d.x, d.y, d.y), pixelSize.xyxy, texcoord.xyxy);

        float4 c;
        c.x = SMAASampleEdges(coords.xy + int2(-1, 0) * pixelSize).g;
        c.y = SMAASampleEdges(coords.xy + int2(0, -1) * pixelSize).r;
        c.zw = SMAASampleEdges(coords.zw + int2(1, 0) * pixelSize).gr;

        float2 cc = mad(float2(2.0, 2.0), c.xz, c.yw);
        SMAAMovc(bool2(step(0.9, d.zw)), cc, float2(0.0, 0.0));

        weights += SMAAAreaDiag(d.xy, cc, subsampleIndices.w).gr;
    }

    return weights;
}

float SMAASearchLength(float2 e, float offset)
{
    float2 scale = SMAA_SEARCHTEX_SIZE * float2(0.5, -1.0);
    float2 bias = SMAA_SEARCHTEX_SIZE * float2(offset, 1.0);
    scale += float2(-1.0, 1.0);
    bias += float2(0.5, -0.5);
    scale /= SMAA_SEARCHTEX_PACKED_SIZE;
    bias /= SMAA_SEARCHTEX_PACKED_SIZE;
    return tex2Dlod(SearchSampler, float4(mad(scale, e, bias), 0.0, 0.0)).r;
}

float SMAASearchXLeft(float2 texcoord, float end)
{
    float2 e = float2(0.0, 1.0);

    while (texcoord.x > end && e.g > 0.8281 && e.r == 0.0)
    {
        e = SMAASampleEdges(texcoord);
        texcoord = mad(-float2(2.0, 0.0), ScreenParams.zw, texcoord);
    }

    float offset = mad(-(255.0 / 127.0), SMAASearchLength(e, 0.0), 3.25);
    return mad(ScreenParams.z, offset, texcoord.x);
}

float SMAASearchXRight(float2 texcoord, float end)
{
    float2 e = float2(0.0, 1.0);

    while (texcoord.x < end && e.g > 0.8281 && e.r == 0.0)
    {
        e = SMAASampleEdges(texcoord);
        texcoord = mad(float2(2.0, 0.0), ScreenParams.zw, texcoord);
    }

    float offset = mad(-(255.0 / 127.0), SMAASearchLength(e, 0.5), 3.25);
    return mad(-ScreenParams.z, offset, texcoord.x);
}

float SMAASearchYUp(float2 texcoord, float end)
{
    float2 e = float2(1.0, 0.0);

    while (texcoord.y > end && e.r > 0.8281 && e.g == 0.0)
    {
        e = SMAASampleEdges(texcoord);
        texcoord = mad(-float2(0.0, 2.0), ScreenParams.zw, texcoord);
    }

    float offset = mad(-(255.0 / 127.0), SMAASearchLength(e.gr, 0.0), 3.25);
    return mad(ScreenParams.w, offset, texcoord.y);
}

float SMAASearchYDown(float2 texcoord, float end)
{
    float2 e = float2(1.0, 0.0);

    while (texcoord.y < end && e.r > 0.8281 && e.g == 0.0)
    {
        e = SMAASampleEdges(texcoord);
        texcoord = mad(float2(0.0, 2.0), ScreenParams.zw, texcoord);
    }

    float offset = mad(-(255.0 / 127.0), SMAASearchLength(e.gr, 0.5), 3.25);
    return mad(-ScreenParams.w, offset, texcoord.y);
}

float2 SMAAArea(float2 dist, float e1, float e2, float offset)
{
    float2 texcoord = mad(float2(SMAA_AREATEX_MAX_DISTANCE, SMAA_AREATEX_MAX_DISTANCE),
                          round(4.0 * float2(e1, e2)),
                          dist);

    texcoord = mad(SMAA_AREATEX_PIXEL_SIZE, texcoord, 0.5 * SMAA_AREATEX_PIXEL_SIZE);
    texcoord.y = mad(SMAA_AREATEX_SUBTEX_SIZE, offset, texcoord.y);

    return SMAAAreaSample(texcoord);
}

// Corner patterns

void SMAADetectHorizontalCornerPattern(inout float2 weights,
                                       float4 texcoord,
                                       float2 d)
{
    float2 leftRight = step(d.xy, d.yx);
    float2 rounding = (1.0 - SMAACornerRoundingNorm()) * leftRight;
    rounding /= leftRight.x + leftRight.y;

    if (rounding.x <= 0.0 && rounding.y <= 0.0)
    {
        return;
    }

    float2 factor = float2(1.0, 1.0);
    float2 pixelSize = ScreenParams.zw;

    factor.x -= rounding.x * SMAASampleEdgesPoint(texcoord.xy + int2(0, 1) * pixelSize).r;
    factor.x -= rounding.y * SMAASampleEdgesPoint(texcoord.zw + int2(1, 1) * pixelSize).r;
    factor.y -= rounding.x * SMAASampleEdgesPoint(texcoord.xy + int2(0, -2) * pixelSize).r;
    factor.y -= rounding.y * SMAASampleEdgesPoint(texcoord.zw + int2(1, -2) * pixelSize).r;

    weights *= saturate(factor);
}

void SMAADetectVerticalCornerPattern(inout float2 weights,
                                     float4 texcoord,
                                     float2 d)
{
    float2 leftRight = step(d.xy, d.yx);
    float2 rounding = (1.0 - SMAACornerRoundingNorm()) * leftRight;
    rounding /= leftRight.x + leftRight.y;

    if (rounding.x <= 0.0 && rounding.y <= 0.0)
    {
        return;
    }

    float2 factor = float2(1.0, 1.0);
    float2 pixelSize = ScreenParams.zw;

    factor.x -= rounding.x * SMAASampleEdgesPoint(texcoord.xy + int2(1, 0) * pixelSize).g;
    factor.x -= rounding.y * SMAASampleEdgesPoint(texcoord.zw + int2(1, 1) * pixelSize).g;
    factor.y -= rounding.x * SMAASampleEdgesPoint(texcoord.xy + int2(-2, 0) * pixelSize).g;
    factor.y -= rounding.y * SMAASampleEdgesPoint(texcoord.zw + int2(-2, 1) * pixelSize).g;

    weights *= saturate(factor);
}

// Blend weight calculation

float4 SMAABlendingWeightCalculationPS(float2 texcoord,
                                       float2 pixcoord,
                                       float4 offset[3],
                                       float2 e,
                                       float4 subsampleIndices)
{
    float4 weights = float4(0.0, 0.0, 0.0, 0.0);
    float2 pixelSize = ScreenParams.zw;

    [branch]
    if (e.g > 0.0)
    {
        weights.rg = SMAACalculateDiagWeights(texcoord, pixcoord, e, subsampleIndices);

        [branch]
        if (weights.r == -weights.g)
        {
            float2 d;

            float3 coords;
            coords.x = SMAASearchXLeft(offset[0].xy, offset[2].x);
            coords.y = offset[1].y;
            d.x = coords.x;

            float e1 = SMAASampleEdges(coords.xy).r;

            coords.z = SMAASearchXRight(offset[0].zw, offset[2].y);
            d.y = coords.z;

            d = abs(round(mad(ScreenParams.xx, d, -pixcoord.xx)));

            float2 sqrtD = sqrt(d);

            float e2 = SMAASampleEdges(coords.zy + int2(1, 0) * pixelSize).r;

            weights.rg = SMAAArea(sqrtD, e1, e2, subsampleIndices.y);

            coords.y = texcoord.y;
            float2 horizontalWeights = weights.rg;
            SMAADetectHorizontalCornerPattern(horizontalWeights, coords.xyzy, d);
            weights.rg = horizontalWeights;
        }
        else
        {
            e.r = 0.0;
        }
    }

    [branch]
    if (e.r > 0.0)
    {
        float2 d;

        float3 coords;
        coords.y = SMAASearchYUp(offset[1].xy, offset[2].z);
        coords.x = offset[0].x;
        d.x = coords.y;

        float e1 = SMAASampleEdges(coords.xy).g;

        coords.z = SMAASearchYDown(offset[1].zw, offset[2].w);
        d.y = coords.z;

        d = abs(round(mad(ScreenParams.yy, d, -pixcoord.yy)));

        float2 sqrtD = sqrt(d);

        float e2 = SMAASampleEdges(coords.xz + int2(0, 1) * pixelSize).g;

        weights.ba = SMAAArea(sqrtD, e1, e2, subsampleIndices.x);

        coords.x = texcoord.x;
        float2 verticalWeights = weights.ba;
        SMAADetectVerticalCornerPattern(verticalWeights, coords.xyxz, d);
        weights.ba = verticalWeights;
    }

    return weights;
}

// Resolve

float4 SMAANeighborhoodBlendingPS(float2 texcoord, int2 pixel)
{
    int2 lastPixel = int2(ScreenParams.xy) - 1;
    float4 a;

    a.x = tex2Dfetch(BlendSampler, min(pixel + int2(1, 0), lastPixel)).a;
    a.y = tex2Dfetch(BlendSampler, min(pixel + int2(0, 1), lastPixel)).g;
    a.wz = tex2Dfetch(BlendSampler, pixel).xz;

    if (dot(a, float4(1.0, 1.0, 1.0, 1.0)) < 1e-5)
    {
        return tex2Dfetch(ColorLinearSampler, pixel);
    }

    bool h = max(a.x, a.z) > max(a.y, a.w);

    float4 blendingOffset = float4(0.0, a.y, 0.0, a.w);
    float2 blendingWeight = a.yw;
    SMAAMovc(bool4(h, h, h, h), blendingOffset, float4(a.x, 0.0, a.z, 0.0));
    SMAAMovc(bool2(h, h), blendingWeight, a.xz);
    blendingWeight /= dot(blendingWeight, float2(1.0, 1.0));

    float4 blendingCoord = mad(blendingOffset,
                               float4(ScreenParams.z, ScreenParams.w, -ScreenParams.z, -ScreenParams.w),
                               texcoord.xyxy);

    float4 color = blendingWeight.x * tex2Dlod(ColorLinearSampler, float4(blendingCoord.xy, 0.0, 0.0));
    color += blendingWeight.y * tex2Dlod(ColorLinearSampler, float4(blendingCoord.zw, 0.0, 0.0));

    return color;
}

float4 SMAAResolveCore(float2 texcoord, int2 pixel)
{
    if (SMAADebugMode == 1)
    {
        float2 edges = SMAALoadEdges(pixel);
        return float4(edges, 0.0, 1.0);
    }

    if (SMAADebugMode == 2)
    {
        return tex2Dfetch(BlendSampler, pixel);
    }

    return SMAANeighborhoodBlendingPS(texcoord, pixel);
}

// Pixel-shader fallback

float4 SMAAFullscreenVS(uint vertexID : SV_VertexID) : SV_Position
{
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    return float4(uv * 2.0 - 1.0, 0.0, 1.0);
}

float4 SMAAEdgeDetectionPS(float4 position : SV_Position) : SV_Target
{
    bool hasEdges;
    float2 edges;

    [branch]
    if (SMAAEnableLowContrast)
    {
        edges = SMAAColorEdgeDetectionLowContrastCore(int2(position.xy), hasEdges);
    }
    else
    {
        edges = SMAAColorEdgeDetectionCore(int2(position.xy), hasEdges);
    }

    if (!hasEdges || !any(edges))
    {
        discard;
    }

    return float4(edges, 0.0, 1.0);
}

struct SMAAEdgeOutput
{
    float4 edges : SV_Target0;
    float4 blend : SV_Target1;
};

SMAAEdgeOutput SMAAEdgeDetectionHybridPS(float4 position : SV_Position)
{
    bool hasEdges;
    float2 edges;

    [branch]
    if (SMAAEnableLowContrast)
    {
        edges = SMAAColorEdgeDetectionLowContrastCore(int2(position.xy), hasEdges);
    }
    else
    {
        edges = SMAAColorEdgeDetectionCore(int2(position.xy), hasEdges);
    }

    SMAAEdgeOutput output;
    output.edges = float4(edges, 0.0, 1.0);
    output.blend = 0.0;
    return output;
}

float4 SMAABlendWeightsPS(float4 position : SV_Position) : SV_Target
{
    float2 pixcoord = position.xy;
    float2 texcoord = pixcoord * ScreenParams.zw;
    int2 pixel = int2(pixcoord);

    float2 e = tex2Dfetch(EdgesSampler, pixel).rg;

    float4 offset[3];
    SMAABlendingWeightCalculationOffsets(texcoord, offset);

    return SMAABlendingWeightCalculationPS(texcoord,
                                           pixcoord,
                                           offset,
                                           e,
                                           float4(0.0, 0.0, 0.0, 0.0));
}

float4 SMAAResolvePS(float4 position : SV_Position) : SV_Target
{
    return SMAAResolveCore(position.xy * ScreenParams.zw, int2(position.xy));
}

// Compute path

#if SMAA_COMPUTE_SUPPORTED

groupshared uint g_ActiveIDs[SMAA_ACTIVE_SLOTS];
groupshared uint g_ActiveCount;

[numthreads(SMAA_GROUP_SIZE_X, SMAA_GROUP_SIZE_Y, 1)]
void SMAABlendWeightsCS(uint3 groupID : SV_GroupID, uint3 threadID : SV_GroupThreadID)
{
    const uint groupPixels = SMAA_GROUP_SIZE_X * SMAA_GROUP_SIZE_Y;
    const uint tid = threadID.y * SMAA_GROUP_SIZE_X + threadID.x;
    const uint2 groupSize = uint2(SMAA_GROUP_SIZE_X, SMAA_GROUP_SIZE_Y);
    const uint2 workingArea = groupSize * uint2(1, SMAA_BATCH_SIZE);
    const uint2 screenSize = uint2(ScreenParams.xy);

    if (tid == 0)
    {
        g_ActiveCount = 0;
    }
    barrier();

    [unroll] for (uint batch = 0; batch < SMAA_BATCH_SIZE; ++batch)
    {
        uint id = batch * groupPixels + tid;
        uint2 pos = groupID.xy * workingArea + uint2(id % groupSize.x, id / groupSize.x);

        if (pos.x < screenSize.x && pos.y < screenSize.y)
        {
            float2 edges = tex2Dfetch(EdgesSampler, int2(pos)).rg;

            if (any(edges))
            {
                uint slot = atomicAdd(g_ActiveCount, 1u);
                g_ActiveIDs[slot] = id;
            }
        }
    }

    barrier();

    uint activeCount = g_ActiveCount;
    for (uint activeIndex = tid; activeIndex < activeCount; activeIndex += groupPixels)
    {
        uint id = g_ActiveIDs[activeIndex];
        uint2 pos = groupID.xy * workingArea + uint2(id % groupSize.x, id / groupSize.x);

        float2 e = SMAALoadEdges(int2(pos));
        float2 pixcoord = float2(pos) + 0.5;
        float2 texcoord = pixcoord * ScreenParams.zw;
        float4 offset[3];
        SMAABlendingWeightCalculationOffsets(texcoord, offset);

        float4 weights = SMAABlendingWeightCalculationPS(texcoord,
                                                         pixcoord,
                                                         offset,
                                                         e,
                                                         float4(0.0, 0.0, 0.0, 0.0));

        tex2Dstore(BlendTexStorage, int2(pos), weights);
    }
}

float4 SMAAResolveHybridPS(float4 position : SV_Position) : SV_Target
{
    return SMAAResolveCore(position.xy * ScreenParams.zw, int2(position.xy));
}

#endif // SMAA_COMPUTE_SUPPORTED

// Techniques

#if SMAA_COMPUTE_SUPPORTED

technique SMAA_ACE <
    ui_label = "SMAA-ACE";
    ui_tooltip = "Pixel edge detection with compute blend weights. Clears the edge and blend textures every frame.";
>
{
    pass EdgeDetection
    {
        VertexShader = SMAAFullscreenVS;
        PixelShader = SMAAEdgeDetectionPS;
        RenderTarget0 = EdgesTex;
        RenderTarget1 = BlendTex;
        ClearRenderTargets = true;
        VertexCount = 3;
    }

    pass BlendWeights
    {
        ComputeShader = SMAABlendWeightsCS;
        DispatchSizeX = (BUFFER_WIDTH + SMAA_GROUP_SIZE_X - 1) / SMAA_GROUP_SIZE_X;
        DispatchSizeY = (BUFFER_HEIGHT + SMAA_TILE_HEIGHT - 1) / SMAA_TILE_HEIGHT;
    }

    pass Resolve
    {
        VertexShader = SMAAFullscreenVS;
        PixelShader = SMAAResolveHybridPS;
        VertexCount = 3;
        SRGBWriteEnable = SMAA_SRGB_OUTPUT;
    }
}

#endif // SMAA_COMPUTE_SUPPORTED

#if SMAA_COMPUTE_SUPPORTED
technique SMAA_ACE_Pixel <
    enabled = false;
    ui_label = "SMAA-ACE (Pixel Fallback)";
    ui_tooltip = "Pixel-shader fallback. Enable this on APIs without compute shader support.";
>
#else
technique SMAA_ACE_Pixel <
    ui_label = "SMAA-ACE (Pixel Fallback)";
    ui_tooltip = "Pixel-shader fallback for APIs without compute shader support.";
>
#endif
{
    pass EdgeDetection
    {
        VertexShader = SMAAFullscreenVS;
        PixelShader = SMAAEdgeDetectionPS;
        RenderTarget = EdgesTex;
        ClearRenderTargets = true;
        VertexCount = 3;
    }

    pass BlendWeights
    {
        VertexShader = SMAAFullscreenVS;
        PixelShader = SMAABlendWeightsPS;
        RenderTarget = BlendTex;
        ClearRenderTargets = true;
        VertexCount = 3;
    }

    pass Resolve
    {
        VertexShader = SMAAFullscreenVS;
        PixelShader = SMAAResolvePS;
        VertexCount = 3;
        SRGBWriteEnable = SMAA_SRGB_OUTPUT;
    }
}

#endif // SMAA_ACE_FX
