#include "ReShade.fxh"

#define PHI (1.6180339887498)

uniform uint frame_count < source = "framecount"; >;

struct VSOUT { float4 vpos : SV_POSITION; float2 uv : TEXCOORD0; };

uniform float JitterAmount < \
    ui_label = "Jitter Amount"; \
    ui_min = 0.0; \
    ui_max = 1.0; \
    ui_step = 0.05; \
    ui_type = "slider"; \
    ui_tooltip = "How much the noise moves, which is what causes the AA effect"; \
> = 0.45;

uniform float BlurAmount < \
    ui_label = "Blur Amount"; \
    ui_min = 0.0; \
    ui_max = 1.0; \
    ui_step = 0.05; \
    ui_type = "slider"; \
    ui_tooltip = "How much blurring occurs"; \
> = 0.5;

uniform float EdgeThreshold < \
    ui_label = "Luma Edge Threshold"; \
    ui_min = 0.0; \
    ui_max = 0.5; \
    ui_step = 0.005; \
    ui_type = "slider"; \
    ui_tooltip = "Strength of edge detection, affects what the noise is applied to"; \
> = 0.25;

uniform float ContrastPredicationRange < \
    ui_label = "Contrast predication range"; \
    ui_min = 0.0; \
    ui_max = 1.0; \
    ui_step = 0.05; \
    ui_type = "slider"; \
    ui_tooltip = 
        "The maximum amount by which the threshold is lowered in dark spots.\n"
        "Helps to detect edges in dark spots.\n"
        "\n"
        "Raising both this value and the edgethreshold helps to prevent false\n"
        "postives in bright spots and false negatives in dark spots."; \
> = 0.8;

uniform bool EdgeDebug <
    ui_type = "radio";
> = false;

#define BUFFER_INFO float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)
#define LUMA_WEIGHTS float3(2.0, 6.0, 1.0)

texture2D ColorTex : COLOR;
sampler2D sColorTex { Texture = ColorTex; };

sampler linearBuffer
{
	Texture = ReShade::BackBufferTex;
	AddressU = Clamp; AddressV = Clamp;
	MipFilter = Point; MinFilter = Linear; MagFilter = Linear;
	SRGBTexture = true;
};


// https://www.shadertoy.com/view/ltB3zD
float GetGoldNoise(float2 vpos, float seed){
    float n = frac(tan(distance(vpos * PHI, vpos) * seed) * vpos.x);
    n = isnan(n) ? 0.0 : n;
    return n;
}

void EdgeDetectionVS(
	in uint id : SV_VertexID,
	out float4 position : SV_Position,
	out float2 texcoord : TEXCOORD0,
	out float4 offset[2] : TEXCOORD1
)
{
	PostProcessVS(id, position, texcoord);
	offset[0] = mad(BUFFER_INFO.xyxy, float4(-1.0, 0.0, 0.0, -1.0), texcoord.xyxy);
    offset[1] = mad(BUFFER_INFO.xyxy, float4( 1.0, 0.0, 0.0,  1.0), texcoord.xyxy);
}

void PS_Main(in VSOUT i, out float3 o : SV_Target0, in float4 offset[2] : TEXCOORD1)
{
    float3 curr = tex2D(linearBuffer, i.uv).rgb;
    float3 left = tex2D(linearBuffer, offset[0].xy).rgb;
    float3 top = tex2D(linearBuffer, offset[0].zw).rgb;
    float3 right = tex2D(linearBuffer, offset[1].xy).rgb;
    float3 bottom = tex2D(linearBuffer, offset[1].zw).rgb;

    float ld = dot(abs(curr - left), LUMA_WEIGHTS);
    float td = dot(abs(curr - top), LUMA_WEIGHTS);
    float rd = dot(abs(curr - right), LUMA_WEIGHTS);
    float bd = dot(abs(curr - bottom), LUMA_WEIGHTS);

    float maxDelta = max(max(ld,td), max(rd, bd));

    float currLuma = dot(curr, LUMA_WEIGHTS);

    float scaling = 1.0 - currLuma;

    float threshold = mad(scaling, -(ContrastPredicationRange * EdgeThreshold), EdgeThreshold);

    float edge = step(threshold, maxDelta);

    if(edge < 1.0) {
        if(EdgeDebug) {
            o = float3(0.0,0.0,0.0);
            return;
        }
        discard;
    } else if(EdgeDebug) {
        o = float3(1.0,1.0,1.0);
        return;
    }

    float noise = GetGoldNoise(i.vpos.xy, frame_count % 16 + 1);
    i.uv += (noise * 2.0 - 1.0) * BUFFER_PIXEL_SIZE * JitterAmount;

    float blur = BlurAmount;
    float2 blurDir = float2(blur, 0.0) * BUFFER_PIXEL_SIZE;
    float3 blurredSample = 0.25 * (
        tex2D(sColorTex, i.uv - blurDir.xy).rgb +
        tex2D(sColorTex, i.uv + blurDir.xy).rgb +
        tex2D(sColorTex, i.uv - blurDir.yx).rgb +
        tex2D(sColorTex, i.uv + blurDir.yx).rgb
    );

    o = blurredSample;
}

technique ASAA
{
    pass { VertexShader = EdgeDetectionVS; PixelShader = PS_Main; }
}
