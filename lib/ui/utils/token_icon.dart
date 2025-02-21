import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TokenIcon extends StatefulWidget {
  final String _token;
  final double opacity;
  final double height;

  TokenIcon(this._token, {this.opacity = 1.0, this.height = 32});

  @override
  _TokenIconState createState() => new _TokenIconState();
}

class _TokenIconState extends State<TokenIcon> {
  String _path;
  static Map<String, Color> _colorList = new Map<String, Color>();

  _init() async {
    var path = 'assets/image/' + widget._token.toLowerCase() + '-icon.png';

    try {
      await rootBundle.load(path);

      _path = path;
    } catch (_) {
      _path = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: widget.height,
        height: widget.height,
        child: FutureBuilder(
            future: _init(),
            builder: (_, snapshot) {
              if (_path == null) {
                if (!_colorList.containsKey(widget._token)) {
                  _colorList[widget._token] = Colors.primaries[Random().nextInt(Colors.primaries.length)];
                }

                return SizedBox(
                    width: 32,
                    height: 32,
                    child: Opacity(
                        opacity: widget.opacity,
                        child: CircleAvatar(
                            backgroundColor: _colorList[widget._token],
                            radius: 16,
                            child: Text(widget._token.substring(0, 1).toUpperCase(), style: TextStyle(fontSize: 18, color: Colors.black)))));
              }

              return SizedBox(
                  width: 32,
                  height: 32,
                  child: Opacity(
                      opacity: widget.opacity,
                      child: Image.asset(
                        _path,
                        height: 32,
                      )));
            }));
  }
}
