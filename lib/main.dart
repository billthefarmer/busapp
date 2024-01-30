import 'package:flutter/material.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:latlong_to_osgrid/latlong_to_osgrid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprintf/sprintf.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        appBarTheme: AppBarTheme(
          backgroundColor: ColorScheme.dark().background,
          foregroundColor: ColorScheme.dark().onBackground,
        ),
      ),
      home: const BusApp(),
    ),
  );
}

class BusApp extends StatefulWidget {
  const BusApp({super.key});
  @override
  _BusAppState createState() => _BusAppState();
}

class _BusAppState extends State<BusApp> {
  late AlignOnUpdate _alignPositionOnUpdate;
  late StreamController<double?> _alignPositionStreamController;
  late bool _hasChangedPosition;
  late String _leftText;
  late String _rightText;

  @override
  void initState() {
    super.initState();
    _alignPositionOnUpdate = AlignOnUpdate.always;
    _alignPositionStreamController = StreamController<double?>();
    _hasChangedPosition = false;
    _leftText = '';
    _rightText= '';
  }

  @override
  void dispose() {
    _alignPositionStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var converter = LatLongConverter();
    return Scaffold(
      appBar: AppBar(
        title: Text('BusApp'),
      ),
      body: FlutterMap(
        mapController: MapController(),
        options: MapOptions(
          interactionOptions: InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          initialCenter: LatLng(52.561928, -1.464854),
          initialZoom: 6.5,
          onTap: (tapPosition, point) {
            var osref = converter.getOSGBfromDec(
              point.latitude, point.longitude);
            print('point $point, ${osref.letterRef}');
          },
          // Stop following the location marker on the map if user interacted
          // with the map.
          onPositionChanged: (MapPosition position, bool hasGesture) {
            if (hasGesture &&
              _alignPositionOnUpdate != AlignOnUpdate.never) {
              setState(() =>
                _alignPositionOnUpdate = AlignOnUpdate.never,
              );
            }
            // Zoom in when located, just once
            if (!hasGesture && !_hasChangedPosition) {
              _alignPositionStreamController.add(18);
              _hasChangedPosition = true;
            }
            if (position.center != null) {
              var lat = position.center!.latitude;
              var lng = position.center!.longitude;
              var osref = converter.getOSGBfromDec(lat, lng);
              setState(() =>
                _rightText = sprintf('%2.5f, %2.5f', [lat, lng])
              );
              setState(() =>
                _leftText = '${osref. letterRef}'
              );
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'org.billthefarmer.busapp',
          ),
          CurrentLocationLayer(
            alignPositionStream: _alignPositionStreamController.stream,
            alignPositionOnUpdate: _alignPositionOnUpdate,
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                'flutter_map | © OpenStreetMap contributors',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(_leftText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(_rightText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Follow the location marker on the map when location updated
          // until user interact with the map.
          setState(
            () => _alignPositionOnUpdate = AlignOnUpdate.always,
          );
          // Follow the location marker on the map and zoom the map to
          // level 18.
          _alignPositionStreamController.add(18);
        },
        child: const Icon(
          Icons.my_location,
          color: Colors.black,
        ),
      ),
    );
  }
}
