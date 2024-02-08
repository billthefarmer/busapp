import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:latlong_to_osgrid/latlong_to_osgrid.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
// import 'package:markdown/markdown.dart' as md;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'package:sprintf/sprintf.dart';
import 'dart:async';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
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

  static final MULTI_FORMAT =
  'https://nextbuses.mobi/WebView/BusStopSearch/BusStopSearchResults' +
  '?id=%s&submit=Search';
  static final SINGLE_FORMAT =
  'https://nextbuses.mobi/WebView/BusStopSearch/BusStopSearchResults/' +
  '%s?currentPage=0';
  static final QUERY_FORMAT = 'point(%f,%f)';
  static final STOP_FORMAT = '%s, %s';
  static final URL_FORMAT = 'https://nextbuses.mobi%s';
  static final BUS_FORMAT = '%s: %s';

  static final POINT_PATTERN = RegExp(r'.+POINT\(.+\).+');
  static final SEARCH_PATTERN = RegExp(r'.*searchMap=true.*');
  static final STOP_PATTERN = RegExp(
    r'^((nld|man|lin|bou|ahl|her|buc|shr|dvn|rtl|mer|twr|nth|cor|war|ntm|' +
    r'sta|bfs|nts|cum|sto|blp|wil|che|dor|knt|glo|woc|oxf|brk|chw|wok|' +
    r'dbs|yny|dur|soa|dby|tel|crm|sot|wsx|lan|esu|lec|suf|esx|nwm|dlo|' +
    r'lei|mlt|cej|hal|ham|sur|hrt)[a-z]{5})|[0-9]{8}$');

  late StreamController<double?> _alignPositionStreamController;
  late AlignOnUpdate _alignPositionOnUpdate;
  late TextEditingController _controller;
  late bool _hasChangedPosition;
  late String _leftText;
  late String _rightText;
  late bool _searching;
  late bool _empty;
  late bool _busy;

  @override
  void initState() {
    super.initState();
    _alignPositionStreamController = StreamController<double?>();
    _alignPositionOnUpdate = AlignOnUpdate.always;
    _controller = TextEditingController();
    _hasChangedPosition = false;
    _searching = false;
    _leftText = '';
    _rightText= '';
    _empty = true;
    _busy = false;
  }

  @override
  void dispose() {
    _alignPositionStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final converter = LatLongConverter();
    return Scaffold(
      appBar: AppBar(
        title: Text('BusApp'),
        actions: [
          if (_searching)
          Expanded(
            child: SearchBar(
              controller: _controller,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() =>
                    _searching = false
                  );
                  _controller.clear();
                }
              ),
              trailing: [
                if (!_empty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                  }
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() =>
                      _searching = false
                    );
                    // Search for buses/stops
                    doSearch(_controller.text);
                    _controller.clear();
                  }
                ),
              ],
              hintText: 'Search…',
              onChanged: (value) {
                setState(() =>
                  _empty = value.isEmpty
                );
              },
              onSubmitted: (value) {
                setState(() =>
                  _searching = false
                );
                // Search for buses/stops
                doSearch(value);
                _controller.clear();
              },
              backgroundColor: MaterialStatePropertyAll(
                ColorScheme.dark().background
              ),
              textStyle: MaterialStatePropertyAll(
                Theme.of(context).textTheme.bodyLarge!
                .apply(color: ColorScheme.dark().onBackground)
              ),
              hintStyle: MaterialStatePropertyAll(
                Theme.of(context).textTheme.bodyLarge!
                .apply(color: Colors.grey)
              ),
            )
          )
          else
          Row(
            children:
            [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() =>
                    _searching = true
                  );
                }
              ),
              IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const Help()),
                  );
                }
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'BusApp',
                    applicationVersion: 'Version 1.0',
                    applicationIcon: Image.asset('images/launch_image.png'),
                    applicationLegalese: 'Copyright © Bill Farmer' +
                    '\nLicence GPLv3',
                  );
                }
              ),
            ],
          ),
        ],
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
                _leftText = '${osref.letterRef}'
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
          // Text in four corners showing location, copyright
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                'flutter_map',
                style: Theme.of(context).textTheme.bodySmall!
                .apply(color: Colors.black),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                '© OpenStreetMap contributors',
                style: Theme.of(context).textTheme.bodySmall!
                .apply(color: Colors.black),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(_leftText,
                style: Theme.of(context).textTheme.bodySmall!
                .apply(color: Colors.black),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(_rightText,
                style: Theme.of(context).textTheme.bodySmall!
                .apply(color: Colors.black),
              ),
            ),
          ),
          if (_busy)
          Center(
            child: CircularProgressIndicator(
              color: Colors.indigo
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Follow the location marker on the map when location updated
          // until user interact with the map.
          setState(() =>
            _alignPositionOnUpdate = AlignOnUpdate.always,
          );
          // Follow the location marker on the map and zoom the map to
          // level 18.
          _alignPositionStreamController.add(18);
        },
        child: const Icon(
          Icons.my_location,
        ),
      ),
    );
  }

  void busesFromPoint(TapPosition tapPosition, LatLng point) async {
    if (_searching) {
      setState(() => _searching = false);
      return;
    }
    setState(() => _busy = true );
    final query = sprintf(QUERY_FORMAT,
      [point.latitude, point.longitude]);
    var url = sprintf(MULTI_FORMAT, [query]);
    try {
      var response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final bs = BeautifulSoup(response.body);
        final table = bs!.body!.table;
        final td = table!.find('td');
        final a = td!.p!.a;
        final href = a!.getAttrValue('href');
        url = sprintf(URL_FORMAT, [href]);
        busesFromUrl(url);
      }
    }

    catch (e, s) {
      showError(e);
      print(e);
      print(s);
    }
  }

  void busesFromUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final bs = BeautifulSoup(response.body);
        final title = bs!.body!.h2!.text;
        final table = bs!.body!.table;
        final list = <Widget>[];
        final trs = table!.findAll('tr');
        for (final tr in trs) {
          var td = tr.find('td');
          final bus = td!.p!.a?.text ?? td!.p!.nextSibling!.text;
          final href = td!.p!.a?.getAttrValue('href');
          td = td.nextSibling;
          final dest = td!.p!.text;
          list.add(SimpleDialogOption(
              onPressed: () {
                if (href != null) {
                  final url = sprintf(URL_FORMAT, [href]);
                  setState(() => _busy = true );
                  busesFromUrl(url);
                }
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
        showResults(title, list);
      }
    }
    catch (e, s) {
      showError(e);
      print(e);
      print(s);
    }
  }

  void stopsFromUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final bs = BeautifulSoup(response.body);
        final title = bs!.body!.h2!.text;
        final table = bs!.body!.table;
        final list = <Widget>[];
        final trs = table!.findAll('tr');
        if (title.startsWith('Search')) {
          for (final tr in trs) {
            var td = tr.find('td');
            td = td!.nextSibling;
            final stop = td!.p!.a!.text;
            final href = td!.p!.a!.getAttrValue('href');
            list.add(SimpleDialogOption(
                onPressed: () {
                  final url = sprintf(URL_FORMAT, [href]);
                  setState(() => _busy = true );
                  busesFromUrl(url);
                  Navigator.pop(context);
                },
                child: Text(stop,
                  style: Theme.of(context).textTheme.bodyLarge!
                  .apply(color: ColorScheme.dark().onBackground),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
            ));
          }
          setState(() => _busy = false );
          showResults(title, list);
        }
        else if (title.startsWith('Locations')) {
          for (final tr in trs) {
            var td = tr.find('td')!.nextSibling;
            final loc = td!.p!.a!.text;
            final href = td!.p!.a!.getAttrValue('href');
            list.add(SimpleDialogOption(
                onPressed: () {
                  final url = sprintf(URL_FORMAT, [href]);
                  setState(() => _busy = true );
                  stopsFromUrl(url);
                  Navigator.pop(context);
                },
                child: Text(loc,
                  style: Theme.of(context).textTheme.bodyLarge!
                  .apply(color: ColorScheme.dark().onBackground),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
            ));
          }
          setState(() => _busy = false );
          showResults(title, list);
        }
      }
    }
    catch (e, s) {
      showError(e);
      print(e);
      print(s);
    }
  }

  void doSearch(String value) {
    if (value.isEmpty)
      return;
    if (value.contains(STOP_PATTERN)) {
      final url = sprintf(SINGLE_FORMAT, [value]);
      busesFromUrl(url);
    }
    else {
      final url = sprintf(MULTI_FORMAT, [value]);
      stopsFromUrl(url);
    }
  }

  void showResults(String title, List<Widget> list) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogTheme: DialogTheme.of(context).copyWith(
              backgroundColor: ColorScheme.dark().background,
              titleTextStyle: Theme.of(context).textTheme.headlineSmall!
              .apply(color: ColorScheme.dark().onBackground),
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

  void showError(Object e) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogTheme: DialogTheme.of(context).copyWith(
              backgroundColor: ColorScheme.dark().background,
              titleTextStyle: Theme.of(context).textTheme.headlineSmall!
              .apply(color: ColorScheme.dark().onBackground),
            ),
          ),
          child: AlertDialog(
            title: Text(e.toString()),
            actions: [
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class Help extends StatelessWidget {
  const Help({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BusApp help'),
      ),
      body: const Markdown(data: 'Help'),
    );
  }

  Future<String> loadAsset() async {
    return await rootBundle.loadString('assets/help.md');
  }
}
