//+++++++++++++++++++++++++++++++++++++++++++++++++++++
// Microcontrast Reduction Shader v1.0 by Hybred
// Reduces local contrast while preserving global luminance structure
// GitHub: https://github.com/xHybred/Hybred-Shaders/tree/main/Shaders
//+++++++++++++++++++++++++++++++++++++++++++++++++++++

#include "ReShade.fxh"

//+++++++++++++++++++++++++++++++++++++++++++++++++++++
// UI CONTROLS
//+++++++++++++++++++++++++++++++++++++++++++++++++++++

uniform float Strength <
    ui_type = "slider";
    ui_min = 0.05;
    ui_max = 1.0;
    ui_step = 0.05;
    ui_label = "Reduction Strength";
    ui_tooltip = "Amount of microcontrast suppression";
> = 0.35;

uniform float Radius <
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 4.0;
    ui_step = 0.5;
    ui_label = "Blur Radius";
    ui_tooltip = "Spatial extent of local averaging";
> = 3.0;

uniform float DetailPreserve <
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.05;
    ui_label = "Detail Preservation";
    ui_tooltip = "Retains some fine detail to avoid over-smoothing";
> = 0.05;

//+++++++++++++++++++++++++++++++++++++++++++++++++++++
// SHADER
//+++++++++++++++++++++++++++++++++++++++++++++++++++++

float3 RGBToYCbCr(float3 rgb)
{
    float Y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    float Cb = (rgb.b - Y) * 0.564;
    float Cr = (rgb.r - Y) * 0.713;
    return float3(Y, Cb, Cr);
}

float3 YCbCrToRGB(float3 ycc)
{
    float Y = ycc.x;
    float Cb = ycc.y;
    float Cr = ycc.z;
    float r = Y + 1.403 * Cr;
    float g = Y - 0.344 * Cb - 0.714 * Cr;
    float b = Y + 1.773 * Cb;
    return float3(r, g, b);
}

float3 GaussianBlur(float2 uv, float r)
{
    float3 sum = 0.0;
    float wsum = 0.0;
    float sigma = r * 0.4;
    int irad = int(ceil(r));
    
    for(int x = -irad; x <= irad; x++)
    {
        for(int y = -irad; y <= irad; y++)
        {
            float2 offset = float2(x, y) * ReShade::PixelSize;
            float dist = length(float2(x, y));
            float weight = exp(-dist * dist / (2.0 * sigma * sigma));
            
            sum += tex2D(ReShade::BackBuffer, uv + offset).rgb * weight;
            wsum += weight;
        }
    }
    
    return sum / wsum;
}

float3 PS_MicrocontrastReduce(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 original = tex2D(ReShade::BackBuffer, uv).rgb;
    float3 blurred = GaussianBlur(uv, Radius);
    
    float3 ycc_orig = RGBToYCbCr(original);
    float3 ycc_blur = RGBToYCbCr(blurred);
    
    float local_detail = ycc_orig.x - ycc_blur.x;
    float suppressed_detail = local_detail * (1.0 - Strength + DetailPreserve * Strength);
    
    float3 ycc_result = float3(
        ycc_blur.x + suppressed_detail,
        ycc_orig.y,
        ycc_orig.z
    );
    
    return YCbCrToRGB(ycc_result);
}

//+++++++++++++++++++++++++++++++++++++++++++++++++++++
// TECHNIQUE
//+++++++++++++++++++++++++++++++++++++++++++++++++++++

technique MicrocontrastReducer
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_MicrocontrastReduce;
    }
}