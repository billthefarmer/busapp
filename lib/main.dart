import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:latlong_to_osgrid/latlong_to_osgrid.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'package:sprintf/sprintf.dart';
import 'dart:async';

// main
void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const BusApp(),
    ),
  );
}

// BusApp
class BusApp extends StatefulWidget {
  const BusApp({super.key});
  @override
  _BusAppState createState() => _BusAppState();
}

// BusAppState
class _BusAppState extends State<BusApp> {

  // Formats for urls and results
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

  // Pattern for bus stop codes, begins with authority code, except Scotland
  static final STOP_PATTERN = RegExp(
    r'^((nld|man|lin|bou|ahl|her|buc|shr|dvn|rtl|mer|twr|nth|cor|war|ntm|' +
    r'sta|bfs|nts|cum|sto|blp|wil|che|dor|knt|glo|woc|oxf|brk|chw|wok|' +
    r'dbs|yny|dur|soa|dby|tel|crm|sot|wsx|lan|esu|lec|suf|esx|nwm|dlo|' +
    r'lei|mlt|cej|hal|ham|sur|hrt)[a-z]{5})|[0-9]{8}$');

  // State variables
  late StreamController<double?> _alignPositionStreamController;
  late AlignOnUpdate _alignPositionOnUpdate;
  late TextEditingController _controller;
  late bool _hasChangedPosition;
  late String _leftText;
  late String _rightText;
  late bool _searching;
  late bool _empty;
  late bool _busy;

  // initState
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

  // dispose
  @override
  void dispose() {
    _alignPositionStreamController.close();
    super.dispose();
  }

  // build
  @override
  Widget build(BuildContext context) {
    final converter = LatLongConverter();
    return Scaffold(
      appBar: AppBar(
        title: Text('BusApp'),
        actions: [
          // Conditional search bar
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
              textStyle: MaterialStatePropertyAll(
                Theme.of(context).textTheme.bodyLarge
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
              // Search
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() =>
                    _searching = true
                  );
                }
              ),
              // Help
              IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: () {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (context) => const Help()),
                  );
                }
              ),
              // About
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () async {
                  PackageInfo packageInfo = await PackageInfo.fromPlatform();
                  showAboutDialog(
                    context: context,
                    applicationName: packageInfo.appName,
                    applicationVersion: 'Version ${packageInfo.version}',
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
      // Map
      body: FlutterMap(
        mapController: MapController(),
        options: MapOptions(
          interactionOptions: InteractionOptions(
            // No rotation, only works on touch screen anyway
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            // Centre of GB, possibly
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
            // Show position in top corners
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
          // Show position
          CurrentLocationLayer(
            alignPositionStream: _alignPositionStreamController.stream,
            alignPositionOnUpdate: _alignPositionOnUpdate,
          ),
          // Text in four corners showing location, copyright
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text('flutter_map',
                style: Theme.of(context).textTheme.bodySmall!
                .apply(color: Colors.black),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text('© OpenStreetMap contributors',
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
          // Show busy
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

  // busesFromPoint
  void busesFromPoint(TapPosition tapPosition, LatLng point) async {
    // Close search bar
    if (_searching) {
      setState(() => _searching = false);
      return;
    }
    // Set busy
    setState(() => _busy = true );
    // Create query
    final query = sprintf(QUERY_FORMAT,
      [point.latitude, point.longitude]);
    var url = sprintf(MULTI_FORMAT, [query]);
    // Get response and parse first stop in list
    try {
      var response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final bs = BeautifulSoup(response.body);
        final table = bs!.body!.table;
        final td = table!.find('td');
        final a = td!.p!.a;
        final href = a!.getAttrValue('href');
        // Create query
        url = sprintf(URL_FORMAT, [href]);
        // Search buses
        busesFromUrl(url);
      }
    }

    // Show error dialog
    catch (e, s) {
      showError(e);
      print(e);
      print(s);
    }
  }

  // busesFromUrl
  void busesFromUrl(String url) async {
    // Set busy
    setState(() => _busy = true );
    // Get response and parse buses
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final bs = BeautifulSoup(response.body);
        final title = bs!.body!.h2!.text;
        final table = bs!.body!.table;
        final list = <Widget>[];
        final trs = table!.findAll('tr');
        // Create list of buses with urls, if present
        for (final tr in trs) {
          var td = tr.find('td');
          // Conditional bus text
          final bus = td!.p!.a?.text ?? td!.p!.nextSibling!.text;
          // Conditional href
          final href = td!.p!.a?.getAttrValue('href');
          td = td.nextSibling;
          // Get destination
          final dest = td!.p!.text;
          // Add to list
          list.add(SimpleDialogOption(
              onPressed: () {
                // Add link if href
                if (href != null) {
                  final url = sprintf(URL_FORMAT, [href]);
                  setState(() => _busy = true );
                  busesFromUrl(url);
                }
                // Close dialog
                Navigator.pop(context);
              },
              // add dialog text
              child: Text(sprintf(BUS_FORMAT, [bus, dest]),
                style: Theme.of(context).textTheme.bodyLarge!
                  .apply(color: ColorScheme.dark().onBackground),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
          ));
        }
        // Clear busy, show dialog
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
    // Set busy
    setState(() => _busy = true );
    // Get response and parse stops
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final bs = BeautifulSoup(response.body);
        final title = bs!.body!.h2!.text;
        final table = bs!.body!.table;
        final list = <Widget>[];
        final trs = table!.findAll('tr');
        // Create list of stops with urls
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
        // Create list of locations with urls
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

  // doSearch
  void doSearch(String value) {
    // Check value
    if (value.isEmpty)
      return;
    // If it's a stop, get buses
    if (value.contains(STOP_PATTERN)) {
      final url = sprintf(SINGLE_FORMAT, [value]);
      busesFromUrl(url);
    }
    // Else get stops
    else {
      final url = sprintf(MULTI_FORMAT, [value]);
      stopsFromUrl(url);
    }
  }

  // showResults
  void showResults(String title, List<Widget> list) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        // Force dark theme
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

  // showError
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

// Help
class Help extends StatefulWidget {
  const Help({super.key});

  @override
  _HelpState createState() => _HelpState();
}

// HelpState
class _HelpState extends State<Help> {

  late String _text;

  // initState
  @override
  void initState() {
    super.initState();

    _text = '';
    loadAsset('assets/help.md').then((t) => setState(() => _text = t));
  }

  // build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BusApp help'),
      ),
      body: Markdown(data: _text),
    );
  }

  // loadAsset
  Future<String> loadAsset(String file) async {
    return await rootBundle.loadString(file);
  }
}
