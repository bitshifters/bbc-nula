# BBC Micro VideoNuLA Gallery Demos
By [simondotm](https://github.com/simondotm/bbc-nula/), with thanks to RobC for the hardware itself, and [KieranHJ](https://github.com/kieranhj/) for the B-Em NULA hack.

This project demonstrates the capabilities of the enhanced ULA board created for the BBC Micro by RobC by presenting a slide show of 16-colour MODE 2 images that have been colour quantized to use the most optimal 16-colour palette from the NuLA 12-bit range of 4096 colours.

See the thread on [Stardot forums](http://stardot.org.uk/forums/viewtopic.php?f=3&t=12150&sid=87a683dc7df121a211b4ddda498500e6) for more information about VideoNuLA.

## About MODE 2
The original BBC Micro has a 4-bits-per-pixel display mode, but it is low resolution - 160x256. In theory, it was always capable of displaying 16 unique colours, however the original Video output ULA was only capable of 1 bit/2 level RGB output, so 8 of the colour palette entries were primary colours (black, red, green, yellow, blue, magenta, cyan, white), and the other 8 were 'flashing' variants.

Competitor hardware such as the Amstrad CPC 464 by comparison had 3-level RGB, enabling a palette of 27 colours. Even this small improvement in RGB colour range provided a much more superior display.

The VideoNuLA hardware modification replaces the original ULA with one that has 4-bit RGB output, enabling each of the 16-colours to be reprogrammed with a 12-bit RGB colour palette instead.

So even though the display pixel resolution remains low, the vastly superior quality of graphics that can be rendered with the improved colour bit-depth is frankly amazing.

## About this project
The project simply converts a collection of source images to optimized 16-colour PNG images, which are then converted to BBC Micro screen display format, compressed and assembled into 'volumes' as `.SSD` disk images along with a 6502 gallery program.

*Note for Linux/Mac users: this project was written on a Windows system, so I've no idea how easy it is to port.*

### How it works

There are two parts to the project:

1. The gallery image compiler script
2. The 6502/BBC Micro gallery player program

### Image Compiler

The compiler is a python script that scans all folders and files listed in the `gallery/assets.json` configuration file, processes them, and puts the processed output PNG files into the `gallery/output` folder.

For each file, the script performs the following operations:
* Load (and optionally resize) the source image
* Run the image file through `pngquant` to generate the 16-colour optimized PNG version of the source file 
* Convert the optimized PNG to MODE 2 pixel screen `.BBC` format
* Compress the `.BBC` file using [Exomizer](https://bitbucket.org/magli143/exomizer/wiki/Home)

#### PngQuant

Converting an image from 24-bit RGB (16M colours) to a mere 16-colours requires a bit of colour quantizing code voodoo, and there are various techniques for doing this. However, I have found over the years that none can match the quality of [PngQuant](https://pngquant.org/). It's simply awesome so much of the credit for the quality of the galleries here is thanks to their good work, not mine. :)

PngQuant supports a neat option called `--posterize N` where N is the number of bits available per R/G/B component. This allows the colour quantizer to fully optimize palette choices for the target bit depth, whereas other quantizers can sometimes 'waste' palette entries that are 8-bit colour depth, but not discernable on more primitive hardware.

PngQuant also supports an optional floyd steinberg dither. It's one of the better dithers as it has weighting algorithms that reduce the presence of colour bleed that is often seen with standard error diffusion. Some images work well dithered, some do not. Dithering often has a dramatic impact on the compressed output file size too.

#### BBC File Format
The `.BBC` file format output by the compiler script is essentially a MODE2 screen file format, however since the NuLA requires a 16-colour palette to be set, I cooked up a file format for the gallery player that adds a 64-byte header to the start of the file that contains meta data about the image file:

```
[00] - version (1)
[01] - screen mode (2)
[02] - pixel width of image
[03] - pixel height of image (where 0=256)
[04]...
[15] - 12 bytes of padding
[16] - 16 bytes of 'remapped' BBC palette, each byte represents the BBC colour palette that is closest match to the NULA palette that follows. In this way, it's possible to approximately render these BBC files on standard machines.
[31]...
[32] - 32 bytes of 'NULA' palette data. 16 x 2 bytes, where the format is [nR][GB] [4 bits index|4 bits red][4 bits green|4 bits blue]
[63]...
[64] - 20Kb of screen pixel data follows. 
```

#### Exomizer

The `.BBC` images are compressed using Exomizer. This step allows us to pack far more images onto one 200Kb SSD disk than we might otherwise - typical compression is >50%, but the downside is that the gallery code has to do a bit more work load, unpack and display the images on the BBC Micro.


### Gallery Player

My main motivation for this project was to see how some awesome 'proper' 16-colour images would be on a BBC Micro enhanced with a NuLA.

I knew I'd not be short of images to try out, so I cooked up a general purpose 6502/BBC Micro gallery program that could be easily re-used across lots of `.SSD` 'volumes.

The program works by automatically presenting a slideshow of all image files it can find on a disk called `A.NN` where `NN` is a serial number from `01` and so on. When the program can't find the next number, it simply resets back to `01`.

#### Decompression
Each compressed `.BBC.EXO` screen file is loaded into memory, unpacked, and displayed. The Exomizer decompression isn't all that fast, but it works well.

The gallery program is compatible with BBC Micro but has enhancements for sideways RAM or BBC Master/Compact Shadow RAM.

On a standard BBC Micro, the unpacking is slightly tricky, since the way Exomizer works it cannot support 'in place' decompression. So the file is loaded at the bottom of display RAM, unpacked to 256 bytes BEFORE screen RAM, and then relocated to &3000.

With sideways RAM installed, the program loads the packed image to a SWR bank (therefore the compressed images must always be <16kb) and unpacks it directly to display RAM &3000 (actually 64 bytes before that &2FC0 due to the header), but does not need to relocate.

On a Master, the program takes advantage of Shadow RAM to create a double buffer effect. The hardware can display one image whilst the next image is being loaded and unpacked to the current 'shadow' buffer, which allows a more seamless slide show.

On the non-Master versions, we have to hide the display during image loading & unpacking, otherwise you'd see all of the garbage being loaded and unpacked into memory!

#### Faders
It occurred to me quite late one day that the way NuLA works as an RGB palette register, it would be possible to implement fading by interpolating the palette every vsync. So, there is now some code to do that - it can fade from any given palette to black or vice versa. I was pretty blown away with how easy that was to do with NuLA and how well it worked, it's pretty cool to see a smooth fade working on a good old Beeb!

Have a dig around in the code if you are interested in how it works. It's basically a simple 256-byte look up table.

### Building the disks

Each gallery 'volume' is assembled using one `BeebAsm` source file.

```
; include the generic gallery player source code
INCLUDE "asm/main.asm"
; include the config file containing the list of images to go on this gallery disk
INCLUDE "gallery/output/volume1/config.asm"
```


The `config.asm` file is automatically created by the `compile.py` compiler script, so make sure you run this before assembling any disks.

The way the compiler script works is that for each subfolder within the root `gallery` folder, the script auto-creates a `config.asm` file containing the `BeebAsm` assembler code to store the compressed files onto an `SSD` disk image. It auto calculates the correct load addresses for the compressed files too (since they often change and are a pain to compute by hand).

```
PUTFILE "gallery/output/volume2/simpsons.png.bbc.exo", "A.01", &67af, &2fc0
PUTFILE "gallery/output/volume2/floyd.png.bbc.exo", "A.02", &7bc0, &2fc0
PUTFILE "gallery/output/volume2/archimedes.png.bbc.exo", "A.03", &7d13, &2fc0
... etc
```

You can build the `SSD` disks using `BeebAsm` eg.
```
BeebAsm.exe -v -i bbcnula1.asm -do bbcnula1.ssd -opt 2
```
Or for your convenience I added a:
```
makeall.bat
```
Or you can use my fancy [Beeb VSC](https://marketplace.visualstudio.com/items?itemName=simondotm.beeb-vsc) BeebAsm extension for Visual Studio Code.

## Making your own gallery compilations
Feel free to clone this repo and make your own NuLA galleries.

### Preparing your images
First thing to do is get a collection of images ready for your gallery as follows:
1. Create a new folder in `gallery/images` and call it `mygallery` or something
1. Put some images you like into this folder, and ensure they are 24-bit PNG
3. Resize/Resample all of your images (using GIMP or Photoshop or similar) to 320x256 so that they are aspect correct. If they are tricky sizes, I tended to add black borders or letter box them, but they ultimately **have** to be 320x256 images
4. Now resize the images again to 160x256, but this time remove any aspect lock. They will look horizontally squashed on your PC, but that's fine, because MODE2 pixels are rectangular, not square. They'll turn out just fine on the Beeb, I promise!
5. Note that in the above "resize" steps make sure you use a decent interpolation filter (Linear/Cubic) so that you don't get jaggy edges after the resize, and also make sure the image format is RGB not Indexed pixel format before the resize - again to prevent jaggy edges.
6. Save the processed image - replacing your source image (otherwise the compiler script will try and compile your source image as well which will be the wrong size and everything will go wonky)

You can usually fit about 20-30 images on one `.SSD` disk, depending on how well they compress. The maximum is 30, due to DFS  limitations (31 including the `!Boot` file).

### Processing the Images

Next, run `compile.py`:
* The script will initially auto detect the new folder and stop
* Run it again, and it will now proceed to process all of the new images it has found in `gallery/images/mygallery` and put the optimized BBC versions into `gallery/output/mygallery` along with a handy config.asm file.

### Assembling the Images

Next, either create a new `bbcnulaX.asm` file in the root, or modify an existing `.asm` file so that it includes your new `config.asm` file eg.:
```
INCLUDE "asm/main.asm"
INCLUDE "gallery/output/mygallery/config.asm"
```

Now you can build your disk image:
```
BeebAsm.exe -v -i bbcnulaX.asm -do bbcnulaX.ssd -opt 2
```
Voila! You should have `bbcnulaX.ssd` all ready to go!

### Other notes

#### Overriding image compiler settings
You can add override settings to the `gallery/assets.json` file for the `compile.py` script to use on a per-folder or per-file basis by adding properties to the folder or file object eg.:

```
{
    "root": {
        \\ override settings for all files in 'mygallery' folder
        "mygallery": {
            "dither": 0
        },
        \\ override settings just for 'mygallery/test.png' file
        "mygallery/test.png": {
            "dither": 1
        },
        
        ...
```

Options are:
* `scale <p>` - scale image by p% (default 100%)
* `width <n>` - scale image proportionally to fixed pixel width, will scale up or down
* `height <n>` - scale image proportionally to fixed pixel height, will scale up or down
* `palette <0-256>` - reduce image to an indexed palette image of N colours (PNG images compress over 40% using this option)
* `dither <0/1>` - dither the image

If only `width` or `height` is specified, aspect is maintained

If `width` AND `height` is specified, aspect is not maintained

Any specifed `width` or `height` overrides any `scale` setting

#### Compiler Note:
Note that `compile.py` only compile files that have been updated or had properties in `assets.json` changed since it was last run - bit of a convenience thing as I'm impatient like that, so don't be alarmed if you run it twice and on the second run it doesn't appear to do anything.

If you want to force a full recompile for any reason, there are two options:
1. delete all of the files in the `gallery/output` folder to force a rebuild
2. change the `FORCE_UPDATE` setting in `compile.py` to `True`

The script isn't that smart however, if you move files around in the `gallery/images` folder you'll end up with crud files in the `gallery/output` folder, in which case cleaning the `gallery/output` folders is the best course of action.

## And Finally...

You can report any issues [here](https://github.com/simondotm/bbc-nula/issues).

**Have fun!**




---

#### !!!
*Don't remove the \<meta\> tag or modify below here, as `compile.py` uses it to auto generate the gallery below.*

## Demo Disk Gallery
For your viewing pleasure, here are the gallery volumes I've created so far. The images below are the 16-colour MODE2 versions, and this is 100% what you actually see on a real BBC Micro with the NuLA mod installed!

<meta>

---
### logo
<img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/logo/nula.png' width=160 height=128>
---
### volume1
<img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/aladdin.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/bb.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/castle.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/chess.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/chuckrock.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/dd.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/doom.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/flashback.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/gng.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/gods.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/lemmings.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/lotus.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/minecraft.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/monkey.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/outrun2.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/pokemon.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/pokemonblue.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/populous2.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/rainbow.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/roadrash.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/sf.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/smw.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/smw2.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/sonic.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/storm.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/swiv.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/xenon2.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/zarch.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/zelda.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume1/zool.png' width=160 height=128>
---
### volume2
<img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/archimedes.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/beeb.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/birds.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/cube.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/diamond.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/elite.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/floyd.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/fractal.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/ghostbusters.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/graphics.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/homer.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/laser.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/logo.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/marbles.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/mario.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/neon.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/ray1.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/ray2.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/simpsons.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/spidey.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/teapot.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/terminator.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/tron.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/trooper.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/tut.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume2/woody.png' width=160 height=128>
---
### volume3
<img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume3/earth.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume3/fashion.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume3/lenna.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume3/lighthouse.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume3/monalisa.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume3/moon.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume3/parrot.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume3/sharbat.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/volume3/tiger.png' width=160 height=128>
---
### wip
<img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/wip/crossy.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/wip/parrots.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/wip/populous.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/wip/teapot.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/wip/test.png' width=160 height=128><img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/wip/tut2.png' width=160 height=128>