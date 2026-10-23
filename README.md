# Hybred Shaders

A small collection of ReShade effects focused on motion clarity, edge quality and image texture. Each shader is standalone and can be used on its own or combined with the others.

| Shader | Purpose |
| --- | --- |
| [SMAA-ACE](Shaders/Hybred/SMAA-ACE.fx) | High quality morphological anti-aliasing with a compute blend pass |
| [ASAA](Shaders/Hybred/AsymetricSamplingAA.fx) | Low-latency stochastic anti-aliasing for complex edges |
| [Edge Sharpen](Shaders/Hybred/EdgeSharpen.fx) | Sharpens edges only, with an optional pixelation effect |
| [Microcontrast Reducer](Shaders/Hybred/MicrocontrastReducer.fx) | Softens harsh microcontrast from forced sharpening or ML upscalers |

## Installation

1. Copy the contents of `Shaders/Hybred` into your ReShade `reshade-shaders/Shaders/Hybred` folder.
2. Copy the contents of `Textures` into your ReShade `reshade-shaders/Textures` folder. SMAA-ACE needs `AreaTex.dds` and `SearchTex.dds`.
3. In the ReShade overlay, enable the effects you want from the shader list.

Only SMAA-ACE needs external textures. The other shaders are self-contained `.fx` files.

# SMAA-ACE

### SMAA-ACE Explanation

SMAA-ACE is a hybrid implementation of Subpixel Morphological Anti-Aliasing. A pixel shader finds edges at full resolution, then a compute shader compacts the active edge pixels inside each workgroup and calculates blend weights only for those pixels. The final pass blends the result into the image. Skipping blend weight work for pixels that are not edges keeps the cost of the expensive pass proportional to how much of the screen is actually aliased.

The compute path is available on D3D11, D3D12, OpenGL and Vulkan. On D3D9 and D3D10, where ReShade has no compute shader support, use the **SMAA-ACE (Pixel Fallback)** technique instead. The fallback produces the same visual result with the reference pixel-shader passes. It is important to use the correct path for your API for the best performance.

### SMAA-ACE Recommendations & Info

- Use this instead of another SMAA shader. Running both is redundant and only adds overhead.
- If you also use ASAA, put ASAA above SMAA-ACE so SMAA cleans up the edges ASAA leaves behind.
- **Edge Threshold** controls how large a color difference must be before a pixel counts as an edge. Lower it to catch more subtle edges, raise it if the shader smooths textures or text it should leave alone. The default of `0.100` is a good starting point.
- **Max Search Steps** and **Max Diagonal Steps** set how far the shader looks along an edge. Higher values handle longer, shallower edges better but cost more. Lower them at high resolutions, where edges are shorter in screen space.
- **Corner Rounding** controls how much sharp corners are rounded. The default of `25` matches SMAA. Lower it if corners in the HUD or UI start looking soft.
- **Low-Contrast Edges** adds an adaptive detector that catches edges a fixed threshold misses. It costs roughly 40-55% more in the edge pass, so leave it off unless you need it.
- **CMAA Local Contrast** and **CMAA/SMAA Synergy** refine the low-contrast detector. They only apply when low-contrast edges are enabled.
- Use **Debug View** to check what the shader detects. `Edges` shows the edge mask, `Blend Weights` shows the calculated weights.
- If the image is HDR, SMAA-ACE keeps the native encoding. The sRGB views are only used on 8-bit sRGB swap chains.

# Asymetric Sampling Anti-Aliasing *(ASAA)*

### ASAA Explanation

This form of AA works by randomly sampling the ~~geometry~~ framebuffer within a pixel rather than sampling the ~~geometry~~ framebuffer at the pixel center. Due to persistence of vision successive frames appear blended. As a result the user just sees a smooth image with less jaggies, whereas temporal anti-aliasing adds additional processing steps by jittering and blending a sequence of frames, this anti-aliasing achieves a smooth image with zero impact to performance & no temporal motion issues.

### ASAA Recommendations & Info

- For single player games use [REST addon](https://github.com/4lex4nder/ReshadeEffectShaderToggler/releases) in order to ignore the UI of the game.

- Pair this with a post-process AA like [SMAA](https://github.com/martymcmodding/iMMERSE) or [CMAA2](https://gist.github.com/martymcmodding/aee91b22570eb921f12d87173cacda03) (both by MartyMCModding, his versions are more optimized). SMAA-ACE in this repository also works well for this. Make sure other AA methods go before (above) this shader. Optionally you can also add sharpening after all the shaders if you want, but the more shaders you put on the higher the overhead is.

- Default value is 0.45, higher values increase anti-aliasing but also makes the noise more visible, lower values decrease anti-aliasing but reduce noise. Too high and the noise on edges becomes more distracting than the aliasing would've been. The optimal value for you depends on your resolution & preference.

- This shader is very performance friendly.

**Cons:** Doesn't do as much on simple geometric edges.

**Pros:** Reduces spurious pixels/aliasing on complex shapes (which other post-process AA's can't/don't do well).

# Edge Sharpen

### Edge Sharpen Explanation

This shader sharpens only edges, unlike typical sharpening filters that do the inverse or sharpen everything. It's useful when you want outlines or edges to stand out more. It also includes an optional pixelation effect that mimics the look of aliasing, as if the game were running without anti-aliasing. Both the edge sharpening and pixelation features can be used separately or together.

### Edge Sharpen Recommendations & Info

- **Detection Threshold** decides which edges are affected. Lower values catch more edges, higher values only touch strong ones.
- **Sample Radius** sets how far the edge detector looks. Raise it for larger, softer edges and lower it for fine detail.
- **Sharpening** and **Pixelation** are independent. Set either to `0` to disable that part of the effect.
- Enable **Show Detection Threshold** while tuning so you can see exactly which pixels are being processed.

# Microcontrast Reducer

### Microcontrast Reducer Explanation

This shader reduces microcontrast, helping soften overly harsh textures that result from artificial clarity boosts *(forced sharpening)* or excessive detail enhancement that can occur with ML-based TAA methods like DLSS 4.

### Microcontrast Reducer Recommendations & Info

- **Reduction Strength** controls how much microcontrast is removed. Start low; small amounts are usually enough to take the edge off.
- **Blur Radius** sets the area used for local averaging. A wider radius smooths larger texture detail, a narrow one targets fine grain.
- **Detail Preservation** keeps some of the original fine detail so the image does not turn into mush. Raise it if the result looks over-smoothed.

### Resources

If you need help, join my [personal Discord server](https://discord.com/invite/dc74er8TJF) or the [Motion Clarity discord](https://discord.gg/JcKNMmDdpT) or the [r/MotionClarity subreddit](https://www.reddit.com/r/MotionClarity/)

**Inspiration:** All code in this shader is original however the inspiration for the ASAA shader was from [ShaderToy Stochastic anti-aliasing](https://www.shadertoy.com/view/mtXcDN) & [Github Gaussian anti-aliasing](https://github.com/bburrough/GaussianAntialiasing), the reason I use the word inspired specifically is because recreating these effects in ReShade are impossible, at least not without an addon so my version is far too different to be called the same or to do these versions justice.

**Credits:** SMAA-ACE uses the original SMAA algorithm, area texture and search texture by Jorge Jimenez, Jose I. Echevarria, Tiago Sousa and Diego Gutierrez, released under the MIT license.

**License:** MIT, see [LICENSE](LICENSE).
