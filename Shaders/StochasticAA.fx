#include "ReShade.fxh"

#define PHI (1.6180339887498)

uniform uint frame_count < source = "framecount"; >;

struct VSOUT { float4 vpos : SV_POSITION; float2 uv : TEXCOORD0; };

uniform float JitterAmount < \
    ui_label = "Jitter Amount"; \
    ui_min = 0.0; \
    ui_max = 2.0; \
    ui_step = 0.001; \
    ui_type = "slider"; \
> = 0.5;

texture2D ColorTex : COLOR;
sampler2D sColorTex { Texture = ColorTex; };

// https://www.shadertoy.com/view/ltB3zD
float GetGoldNoise(float2 vpos, float seed){
    return frac(tan(distance(vpos * PHI, vpos) * seed) * vpos.x);
}

void PS_Main(in VSOUT i, out float4 o : SV_Target0)
{
    i.uv += (GetGoldNoise(i.vpos.xy, frame_count % 8 + 1) * 2.0 - 1.0) * BUFFER_PIXEL_SIZE * JitterAmount;
    o = tex2D(sColorTex, i.uv);
}

technique Stochastic Anti-Aliasing
{
    pass { VertexShader = PostProcessVS; PixelShader = PS_Main; }
}
