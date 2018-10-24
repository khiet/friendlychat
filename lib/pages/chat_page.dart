import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:location/location.dart' as geoloc;

import '../widgets/chat_message.dart';
import '../widgets/chat_text.dart';
import '../widgets/chat_image.dart';
import '../widgets/main_input.dart';

import '../globals/usernames.dart';

class ChatPage extends StatefulWidget {
  final String roomID;

  ChatPage({this.roomID});

  @override
  State<StatefulWidget> createState() {
    return ChatPageState();
  }
}

class ChatPageState extends State<ChatPage> {
  final String _username = (usernames..shuffle()).first;

  List<ChatMessage> _messages = [];
  StreamSubscription<QuerySnapshot> _subscription;
  MainInput _mainInput;

  void chatStreamHandler(QuerySnapshot snapshot) {
    // snapshot.documents.forEach((DocumentSnapshot document) {
    //   print('[chatStreamHandler] ${document.data}');
    // });

    final List<ChatMessage> newMessages = [];
    for (DocumentSnapshot document in snapshot.documents) {
      final Widget message = (document.data['imageUrl'] != null)
          ? ChatImage(imageUrl: document.data['imageUrl'])
          : ChatText(text: document.data['text']);

      newMessages.insert(
        0,
        ChatMessage(
          message: message,
          username: _username,
          sentAt: document.data['createdAt'],
        ),
      );
    }

    setState(() {
      _messages = newMessages;
    });
  }

  void chatInputHandler(String text) {
    setDataFirestore({'text': text});
  }

  void imageHandler(File image) async {
    final Map<String, dynamic> uploadedData = await uploadImage(image);
    setDataFirestore({'imageUrl': uploadedData['imageUrl']});
  }

  void setDataFirestore(Map<String, dynamic> data) {
    Map<String, dynamic> defaultData = {
      'createdAt': DateTime.now(),
    };
    defaultData.addAll(data);

    Firestore.instance
        .collection('rooms')
        .document(widget.roomID)
        .collection('chats')
        .add(defaultData);
  }

  void leaveRoom() {
    Map<String, dynamic> data = {'active': false};

    Firestore.instance
        .collection('rooms')
        .document(widget.roomID)
        .updateData(data);
  }

  Future<Map<String, dynamic>> uploadImage(File image) async {
    final List<String> mimeTypeData = lookupMimeType(image.path).split('/');
    final file = await http.MultipartFile.fromPath(
      'image',
      image.path,
      contentType: MediaType(
        mimeTypeData[0],
        mimeTypeData[1],
      ),
    );
    final http.MultipartRequest imageUploadRequest = http.MultipartRequest(
      'POST',
      Uri.parse(
        'https://us-central1-hchat-app.cloudfunctions.net/storeImage',
      ),
    );

    imageUploadRequest.files.add(file);

    try {
      final http.StreamedResponse streamedResponse =
          await imageUploadRequest.send();
      final http.Response response =
          await http.Response.fromStream(streamedResponse);
      if (response.statusCode != 200 && response.statusCode != 201) {
        return null;
      } else {
        final Map<String, dynamic> responseData = json.decode(response.body);
        return responseData;
      }
    } catch (error) {
      print(error);
      return null;
    }
  }

  void setUserLocation() async {
    final geoloc.Location location = geoloc.Location();
    try {
      final Map<String, double> currentLocation = await location.getLocation();
      print(
        '[currentLocation] ${currentLocation['latitude']} ${currentLocation['longitude']}',
      );
    } catch (error) {
      print('ERROR: ' + error);
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('LOCATION UNAVAILABLE'),
            content: Text('CANNOT FETCH LOCATION'),
            actions: <Widget>[
              FlatButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'),
              )
            ],
          );
        },
      );
    }
  }

  @override
  void dispose() {
    print('[dispose (ChatPage)]');
    _subscription.cancel();
    super.dispose();
  }

  @override
  void initState() {
    print('[initState (ChatPage)]');
    super.initState();

    setUserLocation();
    _subscription = Firestore.instance
        .collection('rooms')
        .document(widget.roomID)
        .collection('chats')
        .snapshots()
        .listen(chatStreamHandler);

    _mainInput = MainInput(
      chatInputHandler: chatInputHandler,
      imageHandler: imageHandler,
    );
  }

  @override
  Widget build(BuildContext context) {
    print('[build (ChatPage)]');

    return WillPopScope(
      onWillPop: () {
        leaveRoom();
        Navigator.of(context).pop();
        return Future.value(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "HChat: ${widget.roomID}",
            style: Theme.of(context).textTheme.subhead,
          ),
          elevation:
              Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0,
        ),
        body: Container(
          decoration: Theme.of(context).platform == TargetPlatform.iOS
              ? BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey[200]),
                  ),
                )
              : null,
          child: Column(
            children: <Widget>[
              Flexible(
                child: ListView.builder(
                  padding: EdgeInsets.all(8.0),
                  reverse: true,
                  itemBuilder: (_, int index) {
                    return _messages[index];
                  },
                  itemCount: _messages.length,
                ),
              ),
              Divider(height: 1.0),
              Container(
                decoration: BoxDecoration(color: Theme.of(context).cardColor),
                child: _mainInput,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
