cd images

for %%x in (*.*) do ..\pngquant -f --speed 1 --nofs --posterize 4 --output "quant\%%x" 16 "%%x"
rem pngquant --output output\images\quant\*.png output\images\*.png



pause
