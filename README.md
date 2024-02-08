# Hybred Shaders

**Recommendations**

- For single player games use [REST addon](https://github.com/4lex4nder/ReshadeEffectShaderToggler/releases) in order to ignore the UI of the game.

- Pair this with a post-process AA like [SMAA](https://github.com/martymcmodding/iMMERSE) or [CMAA2](https://gist.github.com/martymcmodding/aee91b22570eb921f12d87173cacda03) (both by MartyMCModding, his versions are more optimized). Make sure other AA methods go before (above) this shader. Optionally you can also add sharpening after all the shaders if you want, but the more shaders you put on the higher the overhead is.

**Info**

- Default value is 0.35, higher values increase anti-aliasing but also makes the noise more visible, lower values decrease anti-aliasing but reduce noise. Too high and the noise on edges becomes more distracting than the aliasing would've been.

- This shader is **very** lightweight, its even lighter than FXAA is so it should cost you nothing to run.

**How It Works**

This form of AA works by randomly sampling the geometry within a pixel rather than sampling the geometry at the pixel center. The idea is brought over from ray-tracing where the color of a pixel is determined by randomly sampling geometry within each pixel. It achieves perceptual smoothing of rendered images with zero impact to rendering performance.


**Why It Works**

Due to persistence of vision successive frames appear blended. As a result the user just sees a smooth image free of jaggies, whereas temporal anti-aliasing adds additional processing steps by jittering and blending a sequence of frames, this anti-aliasing achieves a smooth image with zero impact to performance & no temporal motion issues.

**ReShade Limitations**

- ReShade has no access to the view matrix, as a result it can't combat specular aliasing or pixel crawl, a game added version is much more efficient as a result

- ReShade can only sample against a 2d image of the game, not against the actual geometry like this technique is suppose to do

- This one isn't a ReShade limitation but currently 〰〰the shader does not do edge detection, this is something that can improve in future iterations〰〰 - added Luminance edge detection, although color or depth based would've been better so will revamp in the future

**Resources**

If you need help, join the [Motion Clarity discord](https://discord.gg/JcKNMmDdpT) or the [r/MotionClarity subreddit](https://www.reddit.com/r/MotionClarity/)

Credits: All code in this shader is original however the inspiration for the shader was from [ShaderToy Stochastic anti-aliasing](https://www.shadertoy.com/view/mtXcDN) & [Github Gaussian anti-aliasing](https://github.com/bburrough/GaussianAntialiasing), along with [ShaderToy Gold Noise Uniform Random Static](https://www.shadertoy.com/view/ltB3zD)
