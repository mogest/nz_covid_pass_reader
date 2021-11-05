import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nz_covid_pass_reader/exceptions.dart';

class DidClient {
  Map<String, Map<String, dynamic>> cache = {};

  Future<Map<String, dynamic>> retrieve(String host) async {
    if (cache.containsKey(host)) {
      return Future.value(cache[host]);
    }

    final url = Uri.parse('https://$host//.well-known/did.json');
    final response =
        await http.get(url, headers: {"Accept": "application/json"});

    if (response.statusCode != 200) {
      throw CovidPassException(CovidPassErrorCode.networkError);
    }

    final document = jsonDecode(response.body);
    cache[host] = document;
    return document;
  }
}