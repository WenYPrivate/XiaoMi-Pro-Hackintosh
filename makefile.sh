#!/bin/bash
#set -x # for DEBUGGING

# Created by stevezhengshiqi on 17 April, 2020
#
# Build XiaoMi-Pro EFI release
#
# Reference:
# https://github.com/williambj1/Hackintosh-EFI-Asus-Zephyrus-S-GX531/blob/master/Makefile.sh by @williambj1


# Vars
CLEAN_UP=True
ERR_NO_EXIT=False
GH_API=True
OC_DPR=False
REMOTE=True
VERSION="local"

# Args
while [[ $# -gt 0 ]]; do
  key="$1"

  case "${key}" in
    --IGNORE_ERR)
    ERR_NO_EXIT=True
    shift # past argument
    ;;
    --NO_CLEAN_UP)
    CLEAN_UP=False
    shift # past argument
    ;;
    --NO_GH_API)
    GH_API=False
    shift # past argument
    ;;
    --OC_PRE_RELEASE)
    OC_DPR=True
    shift # past argument
    ;;
    *)
    if [[ "${key}" =~ "--VERSION=" ]]; then
      VERSION="v${key##*=}"
      shift
    else
      shift
    fi
    ;;
  esac
done

# Colors
if [[ -z ${GITHUB_ACTIONS+x} ]]; then
  black=$(tput setaf 0)
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  yellow=$(tput setaf 3)
  blue=$(tput setaf 4)
  magenta=$(tput setaf 5)
  cyan=$(tput setaf 6)
  white=$(tput setaf 7)
  reset=$(tput sgr0)
  bold=$(tput bold)
fi

# WorkSpaceDir
WSDir="$( cd "$(dirname "$0")" || exit 1; pwd -P )/build"
OUTDir="XiaoMi_Pro-${VERSION}"
OUTDir_OC="XiaoMi_Pro-OC-${VERSION}"

# Exit on Network Issue
function networkErr() {
  echo "${yellow}[${reset}${red}${bold} ERROR ${reset}${yellow}]${reset}: Failed to download resources from ${1}, please check your connection!"
  if [[ ${ERR_NO_EXIT} == False ]]; then
    Cleanup
    exit 1
  fi
}

# Exit on Copy Issue
function copyErr() {
  echo "${yellow}[${reset}${red}${bold} ERROR ${reset}${yellow}]${reset}: Failed to copy resources!"
  if [[ ${ERR_NO_EXIT} == False ]]; then
    Cleanup
    exit 1
  fi
}

# Clean Up
function Cleanup() {
  if [[ ${CLEAN_UP} == True ]]; then
    rm -rf "${WSDir}"
  fi
}

# Workaround for Release Binaries that don't include "RELEASE" in their file names (head or grep)
function H_or_G() {
  if [[ "$1" == "VoodooI2C" ]]; then
    HG="head -n 1"
  elif [[ "$1" == "CloverBootloader" ]]; then
    HG="grep -m 1 CloverV2"
  elif [[ "$1" == "IntelBluetoothFirmware" ]]; then
    HG="grep -m 1 IntelBluetooth"
  elif [[ "$1" == "OpenCore-Factory" ]]; then
    HG="grep -m 2 RELEASE | tail +2"
  else
    HG="grep -m 1 RELEASE"
  fi
}

# Download GitHub Release
function DGR() {
  H_or_G "$2"
  local rawURL
  local URL

  if [[ -n ${3+x} ]]; then
    if [[ "$3" == "PreRelease" ]]; then
      tag=""
    elif [[ "$3" == "NULL" ]]; then
      tag="/latest"
    else
      if [[ -n ${GITHUB_ACTIONS+x} || $GH_API == False ]]; then
        tag="/tag/2.0.9"
      else
        # only release_id is supported
        tag="/$3"
      fi
    fi
  else
    tag="/latest"
  fi

  if [[ -n ${GITHUB_ACTIONS+x} || ${GH_API} == False ]]; then
    rawURL="https://github.com/$1/$2/releases$tag"
    URL="https://github.com$(local one=${"$(curl -L --silent "${rawURL}" | grep '/download/' | eval "${HG}" )"#*href=\"} && local two=${one%\"\ rel*} && echo ${two})"
  else
    rawURL="https://api.github.com/repos/$1/$2/releases$tag"
    URL="$(curl --silent "${rawURL}" | grep 'browser_download_url' | eval "${HG}" | tr -d '"' | tr -d ' ' | sed -e 's/browser_download_url://')"
  fi

  if [[ -z ${URL} || ${URL} == "https://github.com" ]]; then
    networkErr "$2"
  fi

  echo "${green}[${reset}${blue}${bold} Downloading ${URL##*\/} ${reset}${green}]${reset}"
  echo "${cyan}"
  cd ./"$4" || exit 1
  curl -# -L -O "${URL}" || networkErr "$2"
  cd - >/dev/null 2>&1 || exit 1
  echo "${reset}"
}

# Download GitHub Source Code
function DGS() {
  local URL="https://github.com/$1/$2/archive/master.zip"
  echo "${green}[${reset}${blue}${bold} Downloading $2.zip ${reset}${green}]${reset}"
  echo "${cyan}"
  cd ./"$3" || exit 1
  curl -# -L -o "$2.zip" "${URL}"|| networkErr "$2"
  cd - >/dev/null 2>&1 || exit 1
  echo "${reset}"
}

# Download Bitbucket Release
function DBR() {
  local Count=0
  local rawURL="https://api.bitbucket.org/2.0/repositories/$1/$2/downloads/"
  local URL
  while  [ ${Count} -lt 3 ];
  do
    URL="$(curl --silent "${rawURL}" | json_pp | grep 'href' | head -n 1 | tr -d '"' | tr -d ' ' | sed -e 's/href://')"
    if [ "${URL:(-4)}" == ".zip" ]; then
      echo "${green}[${reset}${blue}${bold} Downloading ${URL##*\/} ${reset}${green}]${reset}"
      echo "${cyan}"
      curl -# -L -O "${URL}" || networkErr "$2"
      echo "${reset}"
      return
    else
      Count=$((Count+1))
      echo "${yellow}[${bold} WARNING ${reset}${yellow}]${reset}: Failed to download $2, ${Count} Attempt!"
      echo
    fi
  done

  if [ ${Count} -gt 2 ]; then
    # if 3 times is over and still fail to download, exit
    networkErr "$2"
  fi
}

# Download Pre-Built Binaries
function DPB() {
  local URL="https://raw.githubusercontent.com/$1/$2/master/$3"
  echo "${green}[${reset}${blue}${bold} Downloading ${3##*\/} ${reset}${green}]${reset}"
  echo "${cyan}"
  curl -# -L -O "${URL}" || networkErr "${3##*\/}"
  echo "${reset}"
}

# Exclude Trash
function CTrash() {
  if [[ ${CLEAN_UP} == True ]]; then
    find . -maxdepth 1 ! -path "./${OUTDir}" ! -path "./${OUTDir_OC}" -exec rm -rf {} +
  fi
}

# Extract files for Clover
function ExtractClover() {
  # From CloverV2 and AppleSupportPkg v2.0.9
  unzip -d "Clover" "Clover/*.zip" >/dev/null 2>&1
  cp -R "Clover/CloverV2/EFI/BOOT" "${OUTDir}/EFI/" || copyErr
  cp -R "Clover/CloverV2/EFI/CLOVER/CLOVERX64.efi" "${OUTDir}/EFI/CLOVER/" || copyErr
  cp -R "Clover/CloverV2/EFI/CLOVER/tools" "${OUTDir}/EFI/CLOVER/" || copyErr
  local driverItems=(
    "Clover/CloverV2/EFI/CLOVER/drivers/off/UEFI/FileSystem/ApfsDriverLoader.efi"
    "Clover/CloverV2/EFI/CLOVER/drivers/off/UEFI/MemoryFix/AptioMemoryFix.efi"
    "Clover/CloverV2/EFI/CLOVER/drivers/UEFI/AudioDxe.efi"
    "Clover/CloverV2/EFI/CLOVER/drivers/UEFI/FSInject.efi"
    "Clover/Drivers/AppleGenericInput.efi"
    "Clover/Drivers/AppleUiSupport.efi"
  )
  for driverItem in "${driverItems[@]}"; do
    cp -R "${driverItem}" "${OUTDir}/EFI/Clover/drivers/UEFI/" || copyErr
  done
}

# Extract files from OpenCore
function ExtractOC() {
  mkdir -p "${OUTDir_OC}/EFI/OC/Tools" || exit 1
  unzip -d "OpenCore" "OpenCore/*.zip" >/dev/null 2>&1
  cp -R OpenCore/EFI/BOOT "${OUTDir_OC}/EFI/" || copyErr
  cp -R OpenCore/EFI/OC/OpenCore.efi "${OUTDir_OC}/EFI/OC/" || copyErr
  cp -R OpenCore/EFI/OC/Bootstrap "${OUTDir_OC}/EFI/OC/" || copyErr
  local driverItems=(
    "OpenCore/EFI/OC/Drivers/AudioDxe.efi"
    "OpenCore/EFI/OC/Drivers/OpenCanopy.efi"
    "OpenCore/EFI/OC/Drivers/OpenRuntime.efi"
  )
  local toolItems=(
    "OpenCore/EFI/OC/Tools/CleanNvram.efi"
    "OpenCore/EFI/OC/Tools/OpenShell.efi"
  )
  for driverItem in "${driverItems[@]}"; do
    cp -R "${driverItem}" "${OUTDir_OC}/EFI/OC/Drivers/" || copyErr
  done
  for toolItem in "${toolItems[@]}"; do
    cp -R "${toolItem}" "${OUTDir_OC}/EFI/OC/Tools/" || copyErr
  done
}

# Unpack
function Unpack() {
  echo "${green}[${reset}${yellow}${bold} Unpacking ${reset}${green}]${reset}"
  echo
  unzip -qq "*.zip" >/dev/null 2>&1
}

# Install
function Install() {
  # Kexts
  local kextItems=(
    "AppleALC.kext"
    "HibernationFixup.kext"
    "IntelBluetoothFirmware.kext"
    "IntelBluetoothInjector.kext"
    "Lilu.kext"
    "NVMeFix.kext"
    "VoodooI2C.kext"
    "VoodooI2CHID.kext"
    "VoodooPS2Controller.kext"
    "WhateverGreen.kext"
    "hack-tools-master/kexts/EFICheckDisabler.kext"
    "hack-tools-master/kexts/SATA-unsupported.kext"
    "Kexts/SMCBatteryManager.kext"
    "Kexts/SMCLightSensor.kext"
    "Kexts/SMCProcessor.kext"
    "Kexts/VirtualSMC.kext"
    "Release/CodecCommander.kext"
    "Release/NullEthernet.kext"
  )

  for Kextdir in "${OUTDir}/EFI/CLOVER/kexts/Other/" "${OUTDir_OC}/EFI/OC/Kexts/"; do
    mkdir -p "${Kextdir}" || exit 1
    for kextItem in "${kextItems[@]}"; do
      cp -R "${kextItem}" "${Kextdir}" || copyErr
    done
  done

  # Drivers
  for Driverdir in "${OUTDir}/EFI/CLOVER/drivers/UEFI/" "${OUTDir_OC}/EFI/OC/Drivers/"; do
    mkdir -p "${Driverdir}" || exit 1
    cp -R "OcBinaryData-master/Drivers/HfsPlus.efi" "${Driverdir}" || copyErr
  done

  cp -R "VirtualSmc.efi" "${OUTDir}/EFI/CLOVER/drivers/UEFI/" || copyErr

  if [[ ${REMOTE} == True ]]; then
    cp -R "XiaoMi-Pro-Hackintosh-master/wiki/AptioMemoryFix.efi" "${OUTDir}" || copyErr
  else
    cp -R "../wiki/AptioMemoryFix.efi" "${OUTDir}" || copyErr
  fi

  # ACPI
  for ACPIdir in "${OUTDir}/GTX_Users_Read_This/" "${OUTDir_OC}/GTX_Users_Read_This/"; do
    mkdir -p "${ACPIdir}" || exit 1

    # Create README for GTX
    touch "${ACPIdir}/README.txt"

    if [[ ${REMOTE} == True ]]; then
      cp -R "XiaoMi-Pro-Hackintosh-master/EFI/CLOVER/ACPI/patched/SSDT-LGPAGTX.aml" "${ACPIdir}" || copyErr
    else
      cp -R "../EFI/CLOVER/ACPI/patched/SSDT-LGPAGTX.aml" "${ACPIdir}" || copyErr
    fi
  done
  printf "By Steve\n\nBecause Xiaomi-Pro GTX has a slightly different DSDT from Xiaomi-Pro's, SSDT-LGPA need to be modified to fit with Xiaomi-Pro GTX.\n\n1. If you are using Windows or other OS, please ignore all the files start with ._\n\n2. Go to XiaoMi_Pro-%s/EFI/CLOVER/ACPI/patched/ and delete SSDT-LGPA.aml\n\n3. Copy SSDT-LGPAGTX.aml and paste it to the folder in the second step\n\n4. Done and enjoy your EFI folder for GTX" "${VERSION}"> "${OUTDir}/GTX_Users_Read_This/README.txt"
  printf "By Steve\n\nBecause Xiaomi-Pro GTX has a slightly different DSDT from Xiaomi-Pro's, SSDT-LGPA need to be modified to fit with Xiaomi-Pro GTX.\n\n1. If you are using Windows or other OS, please ignore all the files start with ._\n\n2. Go to XiaoMi_Pro-OC-%s/EFI/OC/ACPI/ and delete SSDT-LGPA.aml\n\n3. Copy SSDT-LGPAGTX.aml and paste it to the folder in the second step\n\n4. Open XiaoMi_Pro-OC-%s/EFI/OC/config.plist and find the following code:\n\n<dict>\n\t<key>Comment</key>\n\t<string>Brightness key, pair with LGPA rename</string>\n\t<key>Enabled</key>\n\t<true/>\n\t<key>Path</key>\n\t<string>SSDT-LGPA.aml</string>\n</dict>\n<dict>\n\t<key>Comment</key>\n\t<string>Brightness key for GTX, pair with LGPA rename</string>\n\t<key>Enabled</key>\n\t<false/>\n\t<key>Path</key>\n\t<string>SSDT-LGPAGTX.aml</string>\n</dict>\n\nchange to:\n\n<dict>\n\t<key>Comment</key>\n\t<string>Brightness key, pair with LGPA rename</string>\n\t<key>Enabled</key>\n\t<false/>\n\t<key>Path</key>\n\t<string>SSDT-LGPA.aml</string>\n</dict>\n<dict>\n\t<key>Comment</key>\n\t<string>Brightness key for GTX, pair with LGPA rename</string>\n\t<key>Enabled</key>\n\t<true/>\n\t<key>Path</key>\n\t<string>SSDT-LGPAGTX.aml</string>\n</dict>\n\n5. Done and enjoy your EFI folder for GTX." "${VERSION}" "${VERSION}"> "${OUTDir_OC}/GTX_Users_Read_This/README.txt"

  for ACPIdir in "${OUTDir}/EFI/CLOVER/ACPI/patched/" "${OUTDir_OC}/EFI/OC/ACPI/"; do
    mkdir -p "${ACPIdir}" || exit 1
    if [[ ${REMOTE} == True ]]; then
      cp -R XiaoMi-Pro-Hackintosh-master/EFI/CLOVER/ACPI/patched/*.aml "${ACPIdir}" || copyErr
      rm -rf "${ACPIdir}SSDT-LGPAGTX.aml"
    else
      cp -R ../EFI/CLOVER/ACPI/patched/*.aml "${ACPIdir}" || copyErr
      rm -rf "${ACPIdir}SSDT-LGPAGTX.aml"
    fi
  done

  for ACPIdir in "${OUTDir}" "${OUTDir_OC}"; do
    if [[ ${REMOTE} == True ]]; then
      cp -R XiaoMi-Pro-Hackintosh-master/wiki/*.aml "${ACPIdir}" || copyErr
    else
      cp -R ../wiki/*.aml "${ACPIdir}" || copyErr
    fi
  done

  # Theme
  if [[ ${REMOTE} == True ]]; then
    cp -R "XiaoMi-Pro-Hackintosh-master/EFI/CLOVER/themes" "${OUTDir}/EFI/CLOVER/" || copyErr
  else
    cp -R "../EFI/CLOVER/themes" "${OUTDir}/EFI/CLOVER/" || copyErr
  fi

  cp -R "OcBinaryData-master/Resources" "${OUTDir_OC}/EFI/OC/" || copyErr

  # config & README
  if [[ ${REMOTE} == True ]]; then
    cp -R "XiaoMi-Pro-Hackintosh-master/EFI/CLOVER/config.plist" "${OUTDir}/EFI/CLOVER/" || copyErr
    cp -R "XiaoMi-Pro-Hackintosh-master/EFI/OC/config.plist" "${OUTDir_OC}/EFI/OC/" || copyErr
    for READMEdir in "${OUTDir}" "${OUTDir_OC}"; do
      cp -R {XiaoMi-Pro-Hackintosh-master/README.md,XiaoMi-Pro-Hackintosh-master/README_CN.md} "${READMEdir}" || copyErr
    done
  else
    cp -R "../EFI/CLOVER/config.plist" "${OUTDir}/EFI/CLOVER/" || copyErr
    cp -R "../EFI/OC/config.plist" "${OUTDir_OC}/EFI/OC/" || copyErr
    for READMEdir in "${OUTDir}" "${OUTDir_OC}"; do
      cp -R {../README.md,../README_CN.md} "${READMEdir}" || copyErr
    done
  fi
}

# Patch
function Patch() {
  local unusedItems=(
    "VoodooI2C.kext/Contents/PlugIns/VoodooInput.kext.dSYM"
    "VoodooI2C.kext/Contents/PlugIns/VoodooInput.kext/Contents/_CodeSignature"
    "VoodooPS2Controller.kext/Contents/PlugIns/VoodooInput.kext"
    "VoodooPS2Controller.kext/Contents/PlugIns/VoodooPS2Mouse.kext"
    "VoodooPS2Controller.kext/Contents/PlugIns/VoodooPS2Trackpad.kext"
  )
  for unusedItem in "${unusedItems[@]}"; do
    rm -rf "${unusedItem}"
  done

  cd "OcBinaryData-master/Resources/Audio/" && find . -maxdepth 1 -not -name "OCEFIAudio_VoiceOver_Boot.wav" -delete && cd "${WSDir}" || exit 1
}

# Enjoy
function Enjoy() {
  echo "${red}[${reset}${blue}${bold} Done! Enjoy! ${reset}${red}]${reset}"
  echo
  open ./
}

function DL() {
  ACDT="Acidanthera"

  # Clover
  DGR CloverHackyColor CloverBootloader NULL "Clover"

  # OpenCore
  if [[ ${OC_DPR} == True ]]; then
    DGR williambj1 OpenCore-Factory PreRelease "OpenCore"
  else
    DGR ${ACDT} OpenCorePkg NULL "OpenCore"
  fi

  # Kexts
  local rmKexts=(
    os-x-eapd-codec-commander
    os-x-null-ethernet
  )

  local acdtKexts=(
    Lilu
    VirtualSMC
    WhateverGreen
    AppleALC
    HibernationFixup
    NVMeFix
    VoodooPS2
  )

  for rmKext in "${rmKexts[@]}"; do
    DBR Rehabman "${rmKext}"
  done

  for acdtKext in "${acdtKexts[@]}"; do
    DGR ${ACDT} "${acdtKext}"
  done

  DGR VoodooI2C VoodooI2C
  DGR zxystd IntelBluetoothFirmware

  DGS RehabMan hack-tools

  # UEFI drivers
  DGR ${ACDT} AppleSupportPkg 19214108 "Clover"

  # UEFI
  # DPB ${ACDT} OcBinaryData Drivers/HfsPlus.efi
  DPB ${ACDT} VirtualSMC EfiDriver/VirtualSmc.efi

  # HfsPlus.efi & OC Resources
  DGS ${ACDT} OcBinaryData

  # XiaoMi-Pro ACPI patch
  if [[ ${REMOTE} == True ]]; then
    DGS daliansky XiaoMi-Pro-Hackintosh
  fi
}

function Init() {
  if [[ ${OSTYPE} != darwin* ]]; then
    echo "This script can only run in macOS, aborting"
    exit 1
  fi

  if [[ -d ${WSDir} ]]; then
    rm -rf "${WSDir}"
  fi
  mkdir "${WSDir}" || exit 1
  cd "${WSDir}" || exit 1

  local dirs=(
    "${OUTDir}"
    "${OUTDir_OC}"
    "XiaoMi-Pro-Hackintosh-master"
    "Clover"
    "OpenCore"
  )
  for dir in "${dirs[@]}"; do
    mkdir -p "${dir}" || exit 1
  done

  if [[ "$(dirname "$PWD")" =~ "XiaoMi-Pro-Hackintosh" ]]; then
    REMOTE=False;
  fi
}

function main() {
  Init
  DL
  Unpack
  Patch

  # Installation
  Install
  ExtractClover
  ExtractOC

  # Clean up
  CTrash

  # Enjoy
  Enjoy
}

main
