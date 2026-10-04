@echo off
title Diplomacy Mod Launcher

:: Set the BAR data directory using the standard Windows LocalAppData path
set "BAR_DATA=%LOCALAPPDATA%\Programs\Beyond-All-Reason\data"

:: Point to the exact engine version you are using
set "ENGINE=%BAR_DATA%\engine\recoil_2026.07.04\spring.exe"

echo Launching Diplomacy Mod...
echo Using engine: %ENGINE%
echo Using config: %~dp0start.txt

:: Launch the engine directly, bypassing the Chobby lobby
"%ENGINE%" --write-dir "%BAR_DATA%" --isolation "%~dp0start.txt"
