from os import listdir
from os.path import isfile, join
import os

# hacky script to auto-update the readme with thumbnails of the converted images


rootdir = "output/"
my_file = "../readme.md"

gallery_md = '\n'

for root, directories, filenames in os.walk(rootdir):
    #for directory in directories:
    #    print os.path.join(root, directory) 
    volume = root[root.rfind('/')+1:]
    if len(volume) > 0:
        gallery_md += "\n---\n### " + volume + "\n"

    for filename in filenames: 
        if filename[-4:] == '.png':
            f = os.path.join(root,filename) 
            f = f.replace('\\', '/')
            f = f.replace(rootdir, '')
            s = "<img src='https://github.com/simondotm/bbc-nula/raw/master/output/" + f + "' width=160 height=128>\n"
            gallery_md += s 

file = open(my_file, "r")
readme = file.read()
offset = readme.find("<meta>")
readme = readme[:offset+6]
readme += gallery_md
file = open(my_file, "w")
file.write(readme)

print "readme.md updated."
