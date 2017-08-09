#!/usr/bin/env python
#
# Uses the Pillow fork of Python Imaging Library (PIL) - http://python-pillow.org/ 
#
# On Windows - 
#		Install Python 2.7
# 		Download ez_setup.py from https://bootstrap.pypa.io/ez_setup.py to C:\Python27
# 		run ez_setup.py
# 		From the \Python27\Scripts folder, run easy_install.exe pillow
# 
# On Mac -
#       pip install Pillow
#
# Author: simondotm
#         https://github.com/simondotm

# options
OUTPUT_FORMAT = "png"
FORCE_UPDATE = False		# has to be True atm because configs dont get build properly otherwise (TODO!)
EXO_COMPRESS = True
BEEBASM_ROOT = "gallery/"

# bbc file format
# [version]
# [mode] 
# [pixel width]
# [height in rows where 0 = 256]
# 12 x spare bytes
# 16 x BBC palette maps (index => BBC standard palette colour)
# 32 x NULA palette entries (16 x 2 bytes for NULA registers)

# ----------------
# 64 bytes total

import gzip
import struct
import sys
import binascii
import math
import json
import os
import PIL
import time

from PIL import Image
import PIL.ImageOps  
  
from os import listdir
from os.path import isfile, join
from subprocess import call



# http://pillow.readthedocs.io/en/3.0.x/handbook/image-file-formats.html


def exportMode2(imagefilename):
	image = Image.open(imagefilename)

	if image.mode != "P":
		print "Error: Not indexed format"
		return

	width, height = image.size

	print "beebimage w=" + str(width) + " h=" + str(height)


	pixel_mask = [ 
		0b00000000, 
		0b00000001, 
		0b00000100, 
		0b00000101, 
		0b00010000, 
		0b00010001, 
		0b00010100, 
		0b00010101, 
		0b01000000, 
		0b01000001, 
		0b01000100, 
		0b01000101,
		0b01010000, 
		0b01010001, 
		0b01010100, 
		0b01010101
		]

	screen_data = bytearray()

	# output header
	screen_data.append(1)	# version
	screen_data.append(2)	# mode
	screen_data.append(width)	# width
	screen_data.append(height & 0xff)	# mode
	# padding
	for n in range(0,12):
		screen_data.append(0)

	# get the palette for this image
	palette = image.getpalette()	# returns 256 rgb entries, but we only use the first 16

	# setup the bbc micro primary colours palette array
	beeb_palette = [ (0,0,0), (255,0,0), (0,255,0), (255,255,0), (0,0,255), (255,0,255), (0,255,255), (255,255,255)]

	# bbc palette map - 16 bytes
	for n in range(0,16):
		# find best fit in the beeb palette
		r1 = palette[ n*3 + 0 ]
		g1 = palette[ n*3 + 1 ]
		b1 = palette[ n*3 + 2 ]

		closest_colour = -1
		max_dist = 256*256*3
		for i in range(0,8):

			p = beeb_palette[i]

			r2 = p[0]
			g2 = p[1]
			b2 = p[2]

			dist_r = abs(r1 - r2)
			dist_g = abs(g1 - g2)
			dist_b = abs(b1 - b2)
			dist = (dist_r * dist_r) + (dist_g * dist_g) + (dist_b * dist_b)

			if dist < max_dist:
				max_dist = dist
				closest_colour = i

		# output the colour index for the beeb palette that is closest to the image palette
		#print closest_colour	
		screen_data.append(closest_colour)

	# nula palette map - 32 bytes
	for n in range(0,16):
		i = n*16 & 0xff
		r = (palette[ n*3 + 0 ] >> 4) & 0x0f
		g = (palette[ n*3 + 1 ] & 0xf0)
		b = (palette[ n*3 + 2 ] >> 4) & 0x0f

		screen_data.append( i + r )
		screen_data.append( g + b )


	for row in xrange(height / 8):
		for col in xrange(width / 2):
			for coloffset in xrange(8):
				y = row*8 + coloffset
				x = col * 2 

				#print "x=" + str(x) + ", y=" +str(y)
				p0 = image.getpixel((x+0, y))
				p1 = image.getpixel((x+1, y))

				# mode2 format is %babababa where pixels are [ab]
				byte = pixel_mask[p1] + (pixel_mask[p0]<<1)

				screen_data.append(byte)

	output_filename = imagefilename + ".bbc"
	print "writing beeb file " + output_filename
	bin_file = open(output_filename, 'wb')
	bin_file.write(screen_data)
	bin_file.close()


	if False:
		beeb_filename = os.path.basename(output_filename)
		ext_offset = beeb_filename.find(".")
		beeb_filename = beeb_filename[:ext_offset]
		beeb_filename = "A." + beeb_filename[-7:]
		# might cock up if filenames have more than 7 chars but first 7 chars are the same
	

	#file_size = os.path.getsize(output_filename) 
	#exec_address = format(0x8000 - file_size, 'x')


	if EXO_COMPRESS:
		print "Compressing with exomizer..."
		call(["exomizer", "raw", "-q", "-m", "1024", "-c", output_filename, "-o", output_filename+".exo"])
		# replace the loaded file with exo compressed version
		#output_filename += ".exo"

	if False:
		# add this file to the beeb asm config - we just give them numbers for filenames to make things easier
		file_size = os.path.getsize(output_filename) 
		load_address = format(0x8000 - file_size, 'x')
		
		num_files = beeb_asm_config.count("PUTFILE") + 1
		beeb_filename = "A." + '{num:02d}'.format(num=num_files)

		config = 'PUTFILE "' + BEEBASM_ROOT + output_filename + '", "' + beeb_filename + '", &' + load_address + ', &' + exec_address + '\n'
		beeb_asm_config += config

	#return beeb_asm_config


def updateConfig(imagefilename, beeb_asm_config):
	output_filename = imagefilename + ".bbc"
	file_size = os.path.getsize(output_filename) 
	exec_address = format(0x8000 - file_size, 'x')
	if EXO_COMPRESS:
		# replace the loaded file with exo compressed version
		output_filename += ".exo"

	# add this file to the beeb asm config - we just give them numbers for filenames to make things easier
	file_size = os.path.getsize(output_filename) 
	load_address = format(0x8000 - file_size, 'x')
	
	num_files = beeb_asm_config.count("PUTFILE") + 1
	beeb_filename = "A." + '{num:02d}'.format(num=num_files)

	config = 'PUTFILE "'  + BEEBASM_ROOT + output_filename + '", "' + beeb_filename + '", &' + load_address + ', &' + exec_address + '\n'
	beeb_asm_config += config

	return beeb_asm_config	

class AssetManager:

	_database = { "source" : "", "target" : "", "root" : {} }
	_database_filename = None

	_meta = {}
	_meta_filename = None
	
	_db_folderlist = []
	_db_source_dir = None
	_db_target_dir = None
	_db_root = None

	# constructor - pass in the filename of the VGM
	def __init__(self, database_filename):
		self._database_filename = database_filename
		if not os.path.isfile(database_filename):
			print "No database exists - creating one"
			self.saveDatabase()
		
		# load the database
		self.loadDatabase()
		self.loadMeta()

		

	
	def saveDatabase(self):
		with open(self._database_filename, 'w') as outfile:
			json.dump(self._database, outfile, sort_keys = True, indent = 4, separators = (',', ': ') )	
	
	def saveMeta(self):
		with open(self._meta_filename, 'w') as outfile:
			json.dump(self._meta, outfile, sort_keys = True, indent = 4, separators = (',', ': ') )		
	
	def loadMeta(self):
		self._meta_filename = self._db_target_dir + "/meta.json"
		if not os.path.isfile(self._meta_filename):
			print "No meta file exists - creating one"
			self.saveMeta()	
		else:
			fh = open(self._meta_filename)
			self._meta = json.loads(fh.read())			
		
	def loadDatabase(self):

		fh = open(self._database_filename)
		self._database = json.loads(fh.read())
		#print self._database

		self._db_root = self._database['root']
		self._db_source_dir = self._database['source']
		self._db_target_dir = self._database['target']

		# load folder list
		for folderkey in self._db_root:
			if not folderkey in self._db_folderlist:
				self._db_folderlist.append(folderkey)

		#print "folder list"
		#print self._db_folderlist
		
		# sync database	
		print "scanning folders"
		update_db = False
		new_folders = []
		for folder, subs, files in os.walk(self._db_source_dir):
			path = folder.replace('\\', '/')
			if path.startswith(self._db_source_dir):
				sz = len(self._db_source_dir)
				path = path[sz:]
				if len(path) > 0:
					if not path in self._db_folderlist:
						self._db_folderlist.append(path)
						new_folders.append(path)
						self._db_root[path] = {}
						update_db = True

		#print "done"

		if update_db:
			self.saveDatabase()
			print str(len(new_folders)) + " new folders detected and added to database."
			print "Apply settings if desired, then re-run script to compile."
			exit()
		
	# scan source folder looking for files that are not in the database and add them
	def scanDir(self, dir):
		print ""
	
	
	def syncDatabase(self):
		files = [f for f in listdir(sourcepath) if isfile(join(sourcepath, f))]	
	
	
	
	def compile(self):
		print "Compiling assets..."
		update_count = 0
		
		config_db = {}

		for assetkey in self._db_root:

			asset = self._db_root[assetkey]	

			#print "'" + folder + "'"
			source_path = self._db_source_dir + assetkey + "/"
			target_path = self._db_target_dir + assetkey + "/"

			asset_is_dir = False
			if os.path.isdir(source_path):
				files = [f for f in listdir(source_path) if isfile(join(source_path, f))]
				asset_is_dir = True
				output_dir = target_path
			else:
				files = [ assetkey ]
				source_path = self._db_source_dir
				target_path = self._db_target_dir				
				output_dir = os.path.dirname(target_path + assetkey) + "/"
				#print output_dir
				#print files
			
			if output_dir not in config_db:
				config_db[output_dir] = ""

			# make the target directory if it doesn't exist
			if not os.path.exists(output_dir):
				os.makedirs(output_dir)

			# for each folder we create a beeb asm config file containing the data for each generated file
			beeb_asm_config = config_db[output_dir]
							
			for file in files:
			

				#print "'" + file + "'"
				#print beeb_asm_config
				
				# if we're processing a directory, skip any files we come across that have been added individually to the database
				asset_file = assetkey + "/" + file
				if asset_is_dir and asset_file in self._db_root:
					#print "Skipping overridden asset"
					continue				
				
				source_file = source_path + file
				target_file = target_path + file



				# determine if we need to synchronise the asset based on :
				#     target is missing
				#     target is older than source
				#     asset meta data is absent
				#     asset settings have changed since last compile
				#
				
				update_asset = FORCE_UPDATE
				update_meta = FORCE_UPDATE
				
				# TODO: missing source file should trigger some cleanup of meta data & output files
				if isfile(source_file):
				
					#print source_file + ", " + target_file				
					if not isfile(target_file):
						update_asset = True
					else:
						if os.path.getctime(target_file) < os.path.getctime(source_file):
							update_asset = True
					
					# Trigger update of output AND metadata file if this asset isn't yet in our meta data
					if not target_file in self._meta:
						print "Adding meta file '" + target_file + "'"
						self._meta[target_file] = {}
						update_meta = True
						update_asset = True
					
					# get compile options for this asset
					#   scale - % resample
					#   width - fixed pixel width, will scale up or down
					#   height - fixed pixel height, will scale up or down
					#   retina - output N upsampled versions of the asset, 1 = @2x, 2 = @4x, 3 = @8x etc.
					#   square - force output image to be square (adds padding on smallest dimension)
					#   pad - ensure a % sized border exists (if square is selected, this border will be incorporated)
					#	palette - reduce image to N colour palette (indexed) image
					#	dither - dither image
					#	alpha - export image using just alpha channel info
					#
					#  If only width or height is specified, aspect is maintained
					#  If width AND height is specified, aspect is not maintained
					#  Width or Height overrides scale
					# 
					asset_options = { 'scale' : 0, 'width' : 0, 'height' : 0, 'retina' : 0, 'square' : 0, 'pad' : 0, 'palette' : 16, 'dither' : 0, 'alpha' : 0 }
					#option_scale = 0
					#option_width = 0
					#option_height = 0
					
					#if 'scale' in asset:	option_scale = asset['scale']
					#if 'width' in asset:	option_width = asset['width']
					#if 'height' in asset:	option_height = asset['height']			
				
					for option in asset:
						if option in asset_options:
							asset_options[option] = asset[option]
					

						
					# Also trigger update if compile options have changed for this asset since last compilation
					meta_asset = self._meta[target_file]
					#print "file '" + target_file + "' meta '" + str(meta_asset) + "'"
					def checkObjectForUpdate(obj, key, value):
						#print "checking " + key
						if not key in obj:
							#print "failed key match"
							return True
						else:
							if obj[key] != value:
								#print "failed value match '" + str(obj[key]) + "' != '" + str(value) + "'"
								return True
						return False
						
					#if checkObjectForUpdate(meta_asset, 'scale', option_scale): update_asset = update_meta = True
					#if checkObjectForUpdate(meta_asset, 'width', option_width): update_asset = update_meta = True
					#if checkObjectForUpdate(meta_asset, 'height', option_height): update_asset = update_meta = True
					
					# scan the asset's options, compare with meta data options, and detect any differences
					for option in asset_options:
						if checkObjectForUpdate(meta_asset, option, asset_options[option]):
							update_asset = True
							update_meta = True					

					

					# process asset if it needs to be updated
					if update_asset:
					
						print "Updating '" + target_file + "'"



						option_scale = asset_options['scale']
						option_width = asset_options['width']
						option_height = asset_options['height']
						option_retina = asset_options['retina']
						option_square = asset_options['square']
						option_pad = asset_options['pad']
						option_palette = asset_options['palette']
						option_dither = asset_options['dither']
						option_alpha = asset_options['alpha']
						
						# compile the image
						img = Image.open(source_file)					
						iw = img.size[0]
						ih = img.size[1]		

						if img.mode != 'RGBA' and img.mode != 'RGB':
							img = img.convert('RGB')


				
						# create a white mask image using the source image alpha channel
						if option_alpha != 0:
							if img.mode == 'RGBA':
								r,g,b,a = img.split()
								white_image = Image.new('RGB', (img.width, img.height), (255,255,255))
								wr, wg, wb = white_image.split()							
									
								#rgba_image = Image.merge('RGBA', (r,g,b,a))	
								rgba_image = Image.merge('RGBA', (wr,wg,wb,a))
								img = rgba_image
						
						
						# force image to be square and/or padded
						if option_square != 0 or option_pad != 0:

							rw = iw
							rh = ih

							pad_x = 0
							pad_y = 0
							if option_pad != 0:
								#print "n"

								pad_x = (option_pad * rw / 100) * 2
								pad_y = (option_pad * rh / 100) * 2
								#print "image w=" + str(rw) + " h=" + str(rh) + " padx=" + str(pad_x) + " pady=" + str(pad_y)
								rw += pad_x
								rh += pad_y
								#print "new image w=" + str(rw) + " h=" + str(rh) + " padx=" + str(pad_x) + " pady=" + str(pad_y)
								#xoffset += pad_x / 2
								#yoffset += pad_y / 2
							
							if option_square != 0 and rw != rh:
								#print "do squaring"
								if rw > rh:
									pad_y += (rw - rh)
									rh = rw
									#print "square image w=" + str(rw) + " h=" + str(rh) + " padx=" + str(pad_x) + " pady=" + str(pad_y)
									#print "a"
								else:	
									pad_x += (rh - rw)
									rw = rh
									#print "square image w=" + str(rw) + " h=" + str(rh) + " padx=" + str(pad_x) + " pady=" + str(pad_y)
									#print "b"
							
							xoffset = pad_x / 2
							yoffset = pad_y / 2


								
					
							imode = img.mode
							if imode != 'RGBA':
								imode = 'RGB'

							#print "arse " + imode
							#print "square to " + str(rw) + " x " + str(rh) + " xoff=" + str(xoffset) + " yoff=" + str(yoffset)
							
							# create a new blank canvas at the target size and copy the original image to its centre
							#c = img.getpixel((0,0))	# use the top left colour of the image as the bg color
							c = (0,0,0,0) # use transparent colour as the pad bg color
							newimg = Image.new(imode, (rw, rh), c) 
							newimg.paste(img, (xoffset, yoffset, xoffset+iw, yoffset+ih) )
							img = newimg
							
							iw = img.size[0]
							ih = img.size[1]		

						# apply image scaling - scale, width or height
						scale_ratio_x = 1.0
						scale_ratio_y = 1.0

						if option_scale != 0:
							scale_ratio_x = scale_ratio_y = float(option_scale) / 100.0
						else:	
							if option_width != 0 and option_height == 0:
								scale_ratio_x = scale_ratio_y = float(option_width) / float(iw)
							else:	
								if option_width == 0 and option_height != 0:
									scale_ratio_x = scale_ratio_y = float(option_height) / float(ih)
								else:
									if option_width !=0 and option_height != 0:
										scale_ratio_x = float(option_width) / float(iw)
										scale_ratio_y = float(option_height) / float(ih)
										
						# apply image scaling - scale, width or height
						ow = iw
						oh = ih

						if scale_ratio_x != 1.0 or scale_ratio_y != 1.0:
							ow = int( round( float(iw) * scale_ratio_x ) )
							oh = int( round( float(ih) * scale_ratio_y ) )
							
						
						# we only handle retina for images that are being resized
						if ow != iw or oh != ih:
						
							# if retina option is selected we create variant of the image at multiples of 2x target resolution
							if option_retina != 0:
							
								levels = option_retina
								while levels > 0:
									retina_scale = pow(2, levels)
									retina_w = ow * retina_scale
									retina_h = oh * retina_scale
									
									if retina_w > iw or retina_h > ih:
										print "WARNING: Output retina image at " + str(retina_scale) + "x exceeds source image size - quality will be compromised"
										
									img_retina = img.resize((retina_w, retina_h), PIL.Image.ANTIALIAS)
									
									# convert to indexed palette format if required									
									if option_palette != 0:
										img_retina = img_retina.quantize(option_palette)
									
									
									
									ext_offset = target_file.rfind('.')
									output_filename = target_file[:ext_offset] + "@" + str(retina_scale) + "x" + "." + OUTPUT_FORMAT #target_file[ext_offset:]
									img_retina.save(output_filename, OUTPUT_FORMAT)
									
									# for each retina level required
									levels -= 1
								
							# resample the image to target size
							img = img.resize((ow, oh), PIL.Image.ANTIALIAS)						
						
						# convert to indexed palette format if required
						# TODO: should use convert - http://pillow.readthedocs.io/en/3.0.x/reference/Image.html?highlight=quantize#PIL.Image.Image.convert
						#if option_palette != 0:
						#	img = img.quantize(option_palette, method=2)	
						#	#img = img.convert("P", colors=2, dither=1)#, colors=option_palette, dither=Image.FLOYDSTEINBERG)		
						#	#img = myquantize(img, option_palette)		
						#	#img = img

						# save the processed image
						ext_offset = target_file.rfind('.')
						output_filename = target_file[:ext_offset] + "." + OUTPUT_FORMAT
						#img.save(output_filename, OUTPUT_FORMAT)
						img.save("temp.png", OUTPUT_FORMAT)
						#time.sleep(0.1)	# some dodgy file access going on

						if option_palette != 0:
							# -f --speed 1 --nofs --posterize 4 --output "quant\%%x" 16 "%%x"
							command_line = ["pngquant"]
							#command_line.extend(["--verbose"])
							if option_dither == 0:
								command_line.extend(["--nofs"])
							command_line.extend(["-f", "--speed", "1", "--posterize", "4"])
							#command_line.extend(["--output", output_filename, "16", output_filename])
							command_line.extend(["--output", output_filename, "16", "temp.png"])
							#print command_line
							call(command_line)
							#img = img.quantize(option_palette, method=2)	
							#img = img.convert("P", colors=2, dither=1)#, colors=option_palette, dither=Image.FLOYDSTEINBERG)		
							#img = myquantize(img, option_palette)		
							#img = img						
						
							exportMode2(output_filename)
							#print beeb_asm_config
							#config_db[output_dir] = beeb_asm_config

						# update meta data
						meta_asset['scale'] = option_scale
						meta_asset['width'] = option_width
						meta_asset['height'] = option_height
						meta_asset['retina'] = option_retina
						meta_asset['square'] = option_square
						meta_asset['pad'] = option_pad
						meta_asset['palette'] = option_palette
						meta_asset['dither'] = option_dither
						meta_asset['alpha'] = option_alpha
						
						# output some metrics of processed file
						meta_asset['output_width'] = ow
						meta_asset['output_height'] = oh
						
						# save meta file each update in case script is interrupted
						if update_meta:
							#print "saving meta data"
							self.saveMeta()
					
						update_count += 1

					# update asm config
					ext_offset = target_file.rfind('.')
					output_filename = target_file[:ext_offset] + "." + OUTPUT_FORMAT
					beeb_asm_config = updateConfig(output_filename, beeb_asm_config)
					#print beeb_asm_config
					config_db[output_dir] = beeb_asm_config
					
			print "Processed asset '" + assetkey + "'"


		print "Complete - updated " + str(update_count) + " files"

		#print config_db
		for config in config_db:
			#print config + "config.asm"
			#print config_db[config]		
			#print	

			if True:
				#print "beebasm config " + beeb_asm_config
				config_filename = config + "config.asm"
				print "writing beebasm config file " + config_filename
				bin_file = open(config_filename, 'w')
				bin_file.write(config_db[config])
				bin_file.close()	
		

	
	
	
	

		
	
#----------------------------------------------------------------------------------------------------------------------------
# main
#----------------------------------------------------------------------------------------------------------------------------
	
	
asset_manager = AssetManager("assets.json")
asset_manager.compile()


# hacky script to auto-update the readme with thumbnails of the converted images
if True:

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
				s = "<img src='https://github.com/simondotm/bbc-nula/raw/master/gallery/output/" + f + "' width=160 height=128>\n"
				gallery_md += s 

	file = open(my_file, "r")
	readme = file.read()
	offset = readme.find("<meta>")
	readme = readme[:offset+6]
	readme += gallery_md
	file = open(my_file, "w")
	file.write(readme)

	print "readme.md updated."