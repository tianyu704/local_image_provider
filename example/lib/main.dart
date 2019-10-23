import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_image_provider/local_album.dart';
import 'package:local_image_provider/local_image.dart';
import 'package:local_image_provider/local_image_provider.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  LocalImageProvider localImageProvider = LocalImageProvider();
  int _localImageCount = 0;
  bool _hasPermission = false;
  List<LocalImage> _localImages = [];
  List<LocalAlbum> _localAlbums = [];
  Uint8List _imgBytes;
  bool _hasImage = false;
  String _imgSource;
  String _selectedId;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    bool hasPermission = false;
    List<LocalImage> localImages = [];
    List<LocalAlbum> localAlbums = [];

    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      hasPermission = await localImageProvider.initialize();
      if (hasPermission) {
        localImages =
            await localImageProvider.findAfterTime(needLocation: false);
        localAlbums = await localImageProvider.findAlbums(LocalAlbumType.all);
      }
    } on PlatformException catch (e) {
      print('Local image provider failed: $e');
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _localImages.addAll(localImages);
      _localAlbums.addAll(localAlbums);
      _localImageCount = _localImages.length;
      print('Count is $_localImageCount, length is ${_localImages.length}');
      _hasPermission = hasPermission;
    });
  }

  void switchAlbum(LocalAlbum album) async {
    List<LocalImage> albumImages =
        await localImageProvider.findImagesInAlbum(album.id, 100);
//    List<LocalImage> albumImages = await localImageProvider.findLatest(10000);
    setState(() {
      _localImages.clear();
      _localImages.addAll(albumImages);
    });
    switchImage(
        Platform.isAndroid ? albumImages[0].path : albumImages[0].id, 'Album');
  }

  void switchImage(String imageId, String src) {
    print("aaaaaaaaa=>$imageId");
    localImageProvider.imageBytes(imageId, 200, 200).then((img) {
      setState(
        () {
          _imgBytes = img;
          _hasImage = true;
          _imgSource = src;
          _selectedId = imageId;
        },
      );
    }, onError: (e) {
      print("aaaaaaaaa=>$e");
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Local Image Provider Example'),
        ),
        body: _hasPermission
            ? Container(
                padding: EdgeInsets.all(10),
                child: Column(children: [
                  Text(
                    'Found - Images: ${_localImages.length}; Albums: ${_localAlbums.length}.',
                    style: TextStyle(fontSize: 24),
                  ),
                  Divider(),
                  Row(
                    children: <Widget>[
                      Text('Images', style: TextStyle(fontSize: 20)),
                      RaisedButton(
                        child: Text("Load More"),
                        onPressed: () {
                          _loadMore();
                        },
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      children: _localImages
                          .map(
                            (img) => GestureDetector(
                              onTap: () => switchImage(
                                  Platform.isAndroid ? img.path : img.id,
                                  "Image"),
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 5),
                                child: Text(
                                    'Id: ${img.id}; created: ${img.creationDate}; lon:${img.lon}; lat:${img.lat}; path:${img.path}'),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Divider(),
                  Text('Albums', style: TextStyle(fontSize: 20)),
                  Expanded(
                    child: ListView(
                      children: _localAlbums
                          .map(
                            (album) => GestureDetector(
                                onTap: () => switchAlbum(album),
                                child: Container(
                                  padding: EdgeInsets.symmetric(vertical: 5),
                                  child: Text(
                                      'Title: ${album.title}; id: ${album.id}; cover Id: ${album.coverImgId}'),
                                )),
                          )
                          .toList(),
                    ),
                  ),
                  Expanded(
                    child: _hasImage
                        ? Column(
                            children: <Widget>[
                              Text('Selected: $_imgSource'),
                              Text('Image id: $_selectedId'),
                              Expanded(
                                child: Image.memory(_imgBytes),
                              ),
                            ],
                          )
                        : Center(
                            child: Text(
                                'Tap on an image or album for a preview',
                                style: TextStyle(
                                    fontSize: 20, fontStyle: FontStyle.italic)),
                          ),
                  ),
                ]),
              )
            : Center(child: Text('No permission')),
      ),
    );
  }

  void _loadMore() async {
    num time = 0;
    if (_localImages != null && _localImages.length > 0) {
      time = _localImages[_localImages.length - 1].creationDate;
    }
    List<LocalImage> more =
        await localImageProvider.findLatestAfterTime(time: time);
    _localImages.addAll(more);
    setState(() {});
  }
}
