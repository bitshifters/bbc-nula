@echo off
echo >imagelist.md
cd output
for /r %%x in (*.png) do echo "<img src='https://github.com/simondotm/bbc-nula/raw/master/%%x' width=160 height=128>" >>imagelist.md
pause
