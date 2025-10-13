# Hybred Shaders

# Asymetric Sampling Anti-Aliasing *(ASAA)*

### ASAA Explanation

This form of AA works by randomly sampling the ~~geometry~~ framebuffer within a pixel rather than sampling the ~~geometry~~ framebuffer at the pixel center. Due to persistence of vision successive frames appear blended. As a result the user just sees a smooth image with less jaggies, whereas temporal anti-aliasing adds additional processing steps by jittering and blending a sequence of frames, this anti-aliasing achieves a smooth image with zero impact to performance & no temporal motion issues.

### ASAA Recommendations & Info

- For single player games use [REST addon](https://github.com/4lex4nder/ReshadeEffectShaderToggler/releases) in order to ignore the UI of the game.

- Pair this with a post-process AA like [SMAA](https://github.com/martymcmodding/iMMERSE) or [CMAA2](https://gist.github.com/martymcmodding/aee91b22570eb921f12d87173cacda03) (both by MartyMCModding, his versions are more optimized). Make sure other AA methods go before (above) this shader. Optionally you can also add sharpening after all the shaders if you want, but the more shaders you put on the higher the overhead is.

- Default value is 0.45, higher values increase anti-aliasing but also makes the noise more visible, lower values decrease anti-aliasing but reduce noise. Too high and the noise on edges becomes more distracting than the aliasing would've been. The optimal value for you depends on your resolution & preference.

- This shader is very performance friendly

**Cons:** Doesn't do as much on simple geomtric edges.

**Pros:** Reduces spurious pixels/aliasing on complex shapes (whcih other post-process AA's can't/don't do well).

# Edge Sharpen

### Edge Sharpen Explanation

This shader is a sharpening algorithm that only sharpens edges (compared to other shaders that do the inverse) incase you need outlines or edges to pop more. It also has a pixelation effect that applies to edges to simulate how "aliasing" looks via a shader, as if you're running the game with no anti-aliasing (if you want that). Both components of the shader can be ran independtly of each other or together.

# Microcontrast Reducer

### Microcontrast Reducer Explanation

This shader tones down microcontrast, which can help reduce textures looking unnaturally harsh due to artifcial clarity boosts via forced sharpening or detail amplification that occurs with ML based TAA's like DLSS 4.

### Resources

If you need help, join the [Motion Clarity discord](https://discord.gg/JcKNMmDdpT) or the [r/MotionClarity subreddit](https://www.reddit.com/r/MotionClarity/)

**Inspiration:** All code in this shader is original however the inspiration for the ASAA shader was from [ShaderToy Stochastic anti-aliasing](https://www.shadertoy.com/view/mtXcDN) & [Github Gaussian anti-aliasing](https://github.com/bburrough/GaussianAntialiasing), the reason I use the word inspired specifically is because recreating these effects in ReShade are impossible, at least not without an addon so my version is far too different to be called the same or to do these versions justice.
