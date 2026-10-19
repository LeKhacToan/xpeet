# Shared settings for build scripts. Override with SIM_DEVICE=... scripts/test.sh
SIM_DEVICE="${SIM_DEVICE:-iPhone 15}"
DESTINATION="platform=iOS Simulator,name=${SIM_DEVICE}"
PROJECT="Xpeet.xcodeproj"
SCHEME="Xpeet"
