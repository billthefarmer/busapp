# ![android/app/src/main/res/mipmap-xhdpi/ic_launcher](https://raw.githubusercontent.com/billthefarmer/busapp/main/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png) BusApp [![build](https://github.com/billthefarmer/busapp/actions/workflows/build.yml/badge.svg)](https://github.com/billthefarmer/busapp/actions/workflows/build.yml)

Geographical GB bus stop and bus times finder.

## Intro
Scroll and zoom the map to find a bus stop and tap the map to get bus
times from that stop.

## Search
There are several ways of finding bus times:

 * **Tap the map** &ndash; This will show a list of bus times from the
    nearest stop. You may tap a bus route to get just that route.
 * **Tap the search button** &ndash; Type in a street name and town,
    or postcode and tap the button on the search widget or
    keyboard. This will show a list of bus stops or a list of
    locations. Tap a location to get the list of bus stops.
 * **Tap the search button** &ndash; Type in the eight character code
    on the bus stop sign, if it exists, and tap the button on the
    search widget or keyboard. This will show a list of bus times from
    that stop.

## Location
The map shows a small blue circle in a blue shaded circle. The size of
the circle indicates the accuracy of the location. The current OS
reference is shown in the left upper corner of the map. The current
longitude, latitude are shown in the right upper corner of the map. If
the map is panned, these figures will change to the current map
centre.

## Navigate
You can pan and zoom the map using pinch, expand, and swipe gestures
and the zoom buttons. The floating blue **Locate** button will return
the map to your current location.

## Permissions
The app will ask for location permission. The location permission is
to find out where you are.

## Android
The app works fine, it doesn't appear to cache map tiles, so it takes
a while to load the map.

## iOS
Untested, building requires a Ruby gem which wouldn't install on my
Monterey VM.

## Linux
The app works fine. Location untested.

## Macos
Untested, building requires a Ruby gem which wouldn't install on my
Monterey VM.

## Windows
If you enable location in Windows settings, when tested my desktop was
apparently on the South Downs on the outskirts of Eastbourne. I don't know
how Windows determines location.

## Web
Untested, no point in a web app.
