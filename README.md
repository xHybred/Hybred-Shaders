# Hybred Shaders - ReShade anti-aliasing

**Recommendations**

- For single player games use [REST addon](https://github.com/4lex4nder/ReshadeEffectShaderToggler/releases) in order to ignore the UI of the game.

- Pair this with a post-process AA like [SMAA](https://github.com/martymcmodding/iMMERSE) or [CMAA2](https://gist.github.com/martymcmodding/aee91b22570eb921f12d87173cacda03) (both by MartyMCModding, his versions are more optimized). Make sure other AA methods go before (above) this shader.

**Info**

- Default value is 0.35, higher values increase anti-aliasing levels but increases noise, lower values decrease anti-aliasing but reduce noise. Too high and the noise on edges becomes more distracting than the aliasing would've been.

- This shader is **very** lightweight, its even lighter than FXAA.

If you need help, join the [Motion Clarity discord](https://discord.gg/JcKNMmDdpT) or the [r/MotionClarity subreddit](https://www.reddit.com/r/MotionClarity/)

Credits: All code in this shader is original however the inspiration for the shader was from [ShaderToy Stochastic anti-aliasing](https://www.shadertoy.com/view/mtXcDN) & [Github Gaussian anti-aliasing](https://github.com/bburrough/GaussianAntialiasing), along with [ShaderToy Gold Noise Uniform Random Static](https://www.shadertoy.com/view/ltB3zD)
