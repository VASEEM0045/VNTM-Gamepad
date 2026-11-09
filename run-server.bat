@echo off
title VNTM Gamepad Windows Server
cd /d "%~dp0\VNTMGamepad-Server"
echo Starting VNTM Gamepad Windows Companion Server...
target\release\vntmgamepad-server.exe
pause
