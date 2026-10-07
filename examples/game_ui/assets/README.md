# Button skin

`button-skin.png` is the actual RGBA texture used by the game UI demo, embedded at
compile time in `skin.odin`. The original generated PNG is preserved unchanged.
Runtime upload converts straight alpha to premultiplied alpha for Foster.

Generated with the built-in imagegen tool on 2026-10-07, transparent background.
Nine-slice source insets are 18% of the shorter image dimension; destination
insets are 9–14 logical pixels. Button interaction changes tint and press offset;
the material, rounded corners, bevel and wear all come from the PNG.

Generation prompt:

> Create a production game UI texture asset, one single square rounded button background skin. Orthographic flat front view, perfectly square shape with smoothly rounded corners (corner radius 12% of side), centered, almost filling canvas with only 2% transparent margin. Dark fantasy RPG, refined hand-painted aged bronze metal beveled rim, desaturated brass highlights on upper left rim, dark oxidized teal metal inner edge, dark charcoal teal leather recessed center with clearly visible fine grain and restrained scratches. Center 70% area quiet and uniformly dark for overlay text. Rim thickness around 6% of width, consistent all four sides, corners symmetric. Elegant material detail, not excessive filigree, no symbols, no text, no letters, no icons, no objects, no drop shadow outside shape, no glow. This texture will be rendered using nine-slice scaling into wide short buttons and square inventory slots; edge midpoint strips must be straight and stretchable and center texture subtle. Transparent background outside the rounded square, true alpha, no checkerboard baked into image. Output a single isolated usable game sprite, not a presentation or mockup.
