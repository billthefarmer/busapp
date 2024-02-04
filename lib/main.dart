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

const MULTI_FORMAT =
'https://nextbuses.mobi/WebView/BusStopSearch/BusStopSearchResults' +
'?id=%s&submit=Search';
const SINGLE_FORMAT =
'https://nextbuses.mobi/WebView/BusStopSearch/BusStopSearchResults/' +
'%s?currentPage=0';
const QUERY_FORMAT = 'point(%f,%f)';
const STOP_FORMAT = '%s, %s';
const URL_FORMAT = 'https://nextbuses.mobi%s';
const BUS_FORMAT = '%s: %s';

const POINT_PATTERN = r'.+POINT\(.+\).+';
const SEARCH_PATTERN = r'.*searchMap=true.*';
const STOP_PATTERN =
r'((nld|man|lin|bou|ahl|her|buc|shr|dvn|rtl|mer|twr|nth|cor|war|ntm|' +
r'sta|bfs|nts|cum|sto|blp|wil|che|dor|knt|glo|woc|oxf|brk|chw|wok|' +
r'dbs|yny|dur|soa|dby|tel|crm|sot|wsx|lan|esu|lec|suf|esx|nwm|dlo|' +
r'lei|mlt|cej|hal|ham|sur|hrt)[a-z]{5})|[0-9]{8}';

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
  late bool _busy;

  @override
  void initState() {
    super.initState();
    _alignPositionOnUpdate = AlignOnUpdate.always;
    _alignPositionStreamController = StreamController<double?>();
    _hasChangedPosition = false;
    _leftText = '';
    _rightText= '';
    _busy = false;
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
          // Buses from nearest stop
          onTap: (tapPosition, point) => busesFromPoint(tapPosition, point),
          // Stop following the location marker on the map if user interacted
          // with the map.
          onPositionChanged: (MapPosition position, bool hasGesture) async {
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
                _leftText = '${osref. letterRef}'
              );
              setState(() =>
                _rightText = sprintf('%2.5f, %2.5f', [lat, lng])
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
          if (_busy)
            Center(
              child: CircularProgressIndicator(),
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

  void busesFromPoint(TapPosition tapPosition, LatLng point) async {
    setState(() => _busy = true );
    final query = sprintf(QUERY_FORMAT,
      [point.latitude, point.longitude]);
    var url = sprintf(MULTI_FORMAT, [query]);
    var response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      try {
        var bs = BeautifulSoup(response.body);
        final table = bs!.body!.table;
        final td = table!.find('td');
        final a = td!.p!.a;
        final href = a!.getAttrValue('href');
        url = sprintf(URL_FORMAT, [href]);
        response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          bs = BeautifulSoup(response.body);
          final table = bs!.body!.table;
          final list = <Widget>[];
          final trs = table!.findAll('tr');
          for (final tr in trs) {
            var td = tr.find('td');
            final bus = td!.a!.text;
            td = td.nextSibling;
            final dest = td!.p!.text;
            list.add(SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(sprintf(BUS_FORMAT, [bus, dest]),
                  style: Theme.of(context).textTheme.bodyLarge!
                  .apply(color: ColorScheme.dark().onBackground),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
            ));
          }
          setState(() => _busy = false );
          showBuses(bs!.body!.h2!.text, list);
        }
      }

      catch (e, s) {
        print(e);
        print(s);
      }
    }
  }

  void showBuses(String title, List<Widget> list) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogTheme: DialogTheme.of(context).copyWith(
              backgroundColor: ColorScheme.dark().background,
              titleTextStyle: Theme.of(context).textTheme.headlineSmall!
              .copyWith(
                color: ColorScheme.dark().onBackground),
            ),
          ),
          child: SimpleDialog(
            title: Text(title,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            children: list,
          ),
        );
      }
    );
  }

  void busesFromStop(String stop) async {
  }
}
