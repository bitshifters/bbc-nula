Use asset compiler ?

Basically need to prep source images so they are sized appropriately for PAL 320x256 ratios
Scale image point sampled to half width (160)
Convert to 16 colour using pngquant, due to posterize option, will select more optimal palettes
PNGquant can only do floyd dither

Write a script that can take a bunch of pre-prepared pngs and convert them to BBC format

BBC format is screen data plus palette info. Must be 160x256x16 or 320x256x4. Or include width & height.
Use CRTC to change display size/centre. Width must be multiple of 2 or 4.
Optionally exo compress
Build disk image+gallery program



