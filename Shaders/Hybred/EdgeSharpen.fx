//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// Edge Sharpening by Hybred
// Sharpens edges to reduce edge specific blur, or can also be used to simulate the appearance of disabled anti-aliasing by enhancing jagged edges
// GitHub: https://github.com/xHybred/Hybred-Shaders/tree/main/Shaders
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#include "ReShade.fxh"

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// UI CONTROLS
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

uniform float EdgeThreshold <
    ui_type = "slider";
    ui_min = 0.001;
    ui_max = 0.650;
    ui_step = 0.05;
    ui_label = "Detection Threshold";
    ui_tooltip = "Lower values detect more edges. Higher values detect only strong edges.";
> = 0.30;

uniform float EdgeStrength <
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 5.0;
    ui_step = 0.05;
    ui_label = "Sharpening";
    ui_tooltip = "Adds sharpening to edges.";
> = 0.55;

uniform float PixelationStrength <
    ui_type = "slider";
    ui_min = 0.000;
    ui_max = 3.000;
    ui_step = 0.05;
    ui_label = "Pixelation";
    ui_tooltip = "Adds pixelation effect to edges.";
> = 0.0;

uniform int SampleRadius <
    ui_type = "slider";
    ui_min = 1;
    ui_max = 3;
    ui_step = 1;
    ui_label = "Sample Radius";
    ui_tooltip = "Radius for edge detection sampling. Higher values detect larger edges.";
> = 1;

uniform bool ShowEdges <
    ui_label = "Show Detection Threshold";
    ui_tooltip = "Shows detected edges in white for debugging purposes.";
> = false;

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// FUNCTIONS
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

// Convert RGB to luminance for edge detection
float GetLuminance(float3 color)
{
    return dot(color, float3(0.299, 0.587, 0.114));
}

// Sobel edge detection
float DetectEdges(float2 texcoord)
{
    float2 texelSize = ReShade::PixelSize * SampleRadius;
    
    // Sample surrounding pixels
    float tl = GetLuminance(tex2D(ReShade::BackBuffer, texcoord + float2(-texelSize.x, -texelSize.y)).rgb); // top left
    float tm = GetLuminance(tex2D(ReShade::BackBuffer, texcoord + float2(0.0, -texelSize.y)).rgb);          // top middle
    float tr = GetLuminance(tex2D(ReShade::BackBuffer, texcoord + float2(texelSize.x, -texelSize.y)).rgb);  // top right
    float ml = GetLuminance(tex2D(ReShade::BackBuffer, texcoord + float2(-texelSize.x, 0.0)).rgb);          // middle left
    float mr = GetLuminance(tex2D(ReShade::BackBuffer, texcoord + float2(texelSize.x, 0.0)).rgb);           // middle right
    float bl = GetLuminance(tex2D(ReShade::BackBuffer, texcoord + float2(-texelSize.x, texelSize.y)).rgb);  // bottom left
    float bm = GetLuminance(tex2D(ReShade::BackBuffer, texcoord + float2(0.0, texelSize.y)).rgb);           // bottom middle
    float br = GetLuminance(tex2D(ReShade::BackBuffer, texcoord + float2(texelSize.x, texelSize.y)).rgb);   // bottom right
    
    // Sobel X
    float sobelX = (-1.0 * tl) + (1.0 * tr) +
                   (-2.0 * ml) + (2.0 * mr) +
                   (-1.0 * bl) + (1.0 * br);
    
    // Sobel Y
    float sobelY = (-1.0 * tl) + (-2.0 * tm) + (-1.0 * tr) +
                   (1.0 * bl) + (2.0 * bm) + (1.0 * br);
    
    // Calculate edge magnitude
    float edgeMagnitude = sqrt((sobelX * sobelX) + (sobelY * sobelY));
    
    return edgeMagnitude;
}

// Apply pixelation effect
float3 ApplyPixelation(float2 texcoord, float strength)
{
    if (strength <= 0.0) 
        return tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    // Calculate pixelation grid size
    float pixelSize = 1.0 + strength * 2.0;
    float2 pixelatedCoord = floor(texcoord * ReShade::ScreenSize / pixelSize) * pixelSize / ReShade::ScreenSize;
    pixelatedCoord += (pixelSize * 0.5) / ReShade::ScreenSize; // Center the pixel
    
    return tex2D(ReShade::BackBuffer, pixelatedCoord).rgb;
}

// Enhance edge contrast to create jaggy appearance
float3 EnhanceEdgeContrast(float3 originalColor, float edgeStrength, float2 texcoord)
{
    if (edgeStrength <= 0.0)
        return originalColor;
    
    // Sample neighboring pixels for contrast enhancement
    float2 texelSize = ReShade::PixelSize;
    float3 left = tex2D(ReShade::BackBuffer, texcoord + float2(-texelSize.x, 0.0)).rgb;
    float3 right = tex2D(ReShade::BackBuffer, texcoord + float2(texelSize.x, 0.0)).rgb;
    float3 up = tex2D(ReShade::BackBuffer, texcoord + float2(0.0, -texelSize.y)).rgb;
    float3 down = tex2D(ReShade::BackBuffer, texcoord + float2(0.0, texelSize.y)).rgb;
    
    // Calculate local contrast
    float3 avgNeighbor = (left + right + up + down) * 0.25;
    float3 contrast = originalColor - avgNeighbor;
    
    // Enhance the contrast to create sharper edges
    float3 enhancedColor = originalColor + contrast * edgeStrength;
    
    return enhancedColor;
}

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// PIXEL SHADER
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

float3 AntiAliasingDisablerPS(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    // Get original color
    float3 originalColor = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    // Detect edges
    float edgeValue = DetectEdges(texcoord);
    
    // Debug mode: show edges
    if (ShowEdges)
    {
        return edgeValue > EdgeThreshold ? float3(1.0, 1.0, 1.0) : float3(0.0, 0.0, 0.0);
    }
    
    // Apply pixelation effect first
    float3 pixelatedColor = ApplyPixelation(texcoord, PixelationStrength);
    
    // If edge is detected, enhance it
    if (edgeValue > EdgeThreshold)
    {
        // Enhance edge contrast to create jaggy appearance
        float3 jaggyColor = EnhanceEdgeContrast(pixelatedColor, EdgeStrength, texcoord);
        
        // Blend based on edge strength
        float blendFactor = saturate((edgeValue - EdgeThreshold) * 10.0);
        return lerp(pixelatedColor, jaggyColor, blendFactor);
    }
    
    // For non-edge pixels, apply light pixelation if enabled
    return pixelatedColor;
}

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// TECHNIQUE
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

technique EdgeSharpening
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = AntiAliasingDisablerPS;
    }
}