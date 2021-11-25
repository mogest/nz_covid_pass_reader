import 'package:nz_covid_pass_reader/cose.dart';
import 'package:nz_covid_pass_reader/did_client.dart';
import 'package:nz_covid_pass_reader/exceptions.dart';
import 'package:base32/base32.dart';
import 'dart:typed_data';

class CovidPass {
  String givenName;
  String? familyName;
  DateTime dob;

  CovidPass(this.givenName, this.familyName, this.dob);

  static parse(String url,
      {DidClient? didClient, bool allowTestIssuers = false}) async {
    RegExp exp = RegExp(r"^([^:]+):/([^/]+)/([A-Z2-7]+)$");
    RegExpMatch? matches = exp.firstMatch(url);
    if (matches == null) {
      throw CovidPassException(CovidPassErrorCode.invalidUrl);
    }

    String? scheme = matches.group(1);
    String? majorVersion = matches.group(2);
    String? encodedData = matches.group(3);

    if (scheme != "NZCP" || majorVersion != "1" || encodedData == null) {
      throw CovidPassException(CovidPassErrorCode.invalidUrl);
    }

    final data = _base32decode(encodedData);
    final Cose cose = await decode(data, didClient, allowTestIssuers);

    final vc = cose.payload["vc"];
    if (vc == null ||
        vc["credentialSubject"] == null ||
        vc["type"] == null ||
        vc["@context"] == null ||
        vc["@context"].first != "https://www.w3.org/2018/credentials/v1") {
      throw CovidPassException(CovidPassErrorCode.invalidFormat);
    }

    List type = vc["type"];
    if (type.length != 2 ||
        type.first != "VerifiableCredential" ||
        type.last != "PublicCovidPass") {
      throw CovidPassException(CovidPassErrorCode.invalidFormat);
    }

    final credentialSubject = vc["credentialSubject"];
    final givenName = credentialSubject["givenName"];
    final familyName = credentialSubject["familyName"];
    final dobString = credentialSubject["dob"];

    if (givenName == null || dobString == null) {
      throw CovidPassException(CovidPassErrorCode.invalidFormat);
    }

    final dob = DateTime.parse(dobString);

    return CovidPass(givenName, familyName, dob);
  }

  static Future<Cose> decode(
      List<int> data, DidClient? didClient, bool allowTestIssuers) async {
    final cose = Cose.decode(data);

    final String iss = cose.payload[1];
    final int exp = cose.payload[4];
    final int nbf = cose.payload[5];
    // final Uint8Buffer cti = cose.payload[7];

    int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now > exp) {
      throw CovidPassException(CovidPassErrorCode.expired);
    }
    if (now < nbf) {
      throw CovidPassException(CovidPassErrorCode.notYetValid);
    }

    if (iss != "did:web:nzcp.identity.health.nz" &&
        (!allowTestIssuers || iss != "did:web:nzcp.covid19.health.nz")) {
      throw CovidPassException(CovidPassErrorCode.invalidIssuer);
    }

    final host = iss.split(":").last;
    final didDocument = await (didClient ?? DidClient()).retrieve(host);
    final keyReference = "$iss#${cose.kid}";

    final List<dynamic> methods = didDocument["verificationMethod"];

    Map<String, dynamic> method;
    try {
      method = methods.firstWhere((method) => method["id"] == keyReference);
    } on StateError {
      throw CovidPassException(CovidPassErrorCode.missingPublicKey);
    }

    final jwk = method["publicKeyJwk"];
    cose.verify(jwk); // throws if validation fails

    return cose;
  }

  static Uint8List _base32decode(String encodedData) {
    try {
      final remainder = encodedData.length % 8;
      final paddingRequired = remainder == 0 ? 0 : 8 - remainder;
      final padding = "=" * paddingRequired;
      final paddedData = encodedData + padding;
      return base32.decode(paddedData);
    } on FormatException {
      throw CovidPassException(CovidPassErrorCode.invalidUrl);
    }
  }
}
