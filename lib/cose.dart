import 'dart:typed_data';
import 'package:nz_covid_pass_reader/exceptions.dart';
import 'package:typed_data/typed_buffers.dart' show Uint8Buffer;
import 'package:cbor/cbor.dart';
import 'package:x509b/x509.dart';

class Cose {
  Uint8Buffer protectedHeader, payloadBytes, signers;
  String kid;
  int alg;
  Map<dynamic, dynamic> payload;

  static const cborDataLength = 4;
  static const cborDataProtectedHeaderIndex = 0;
  static const cborDataPayloadBytesIndex = 2;
  static const cborDataSignerIndex = 3;

  Cose(this.protectedHeader, this.payloadBytes, this.signers,
      this.kid, this.alg, this.payload);

  factory Cose.decode(List<int> cose) {
    final items = parseItems(cose);
    final protectedHeader = items[cborDataProtectedHeaderIndex];
    final payloadBytes = items[cborDataPayloadBytesIndex];
    final signers = items[cborDataSignerIndex];
    final header = parseHeader(protectedHeader);
  
    return Cose(protectedHeader, payloadBytes, signers,
        parseKid(header), header[1], parsePayload(payloadBytes));
  }

  static List parseItems(List<int> cose) {
    var inst = Cbor();
    inst.decodeFromList(cose);
    List<dynamic>? data = inst.getDecodedData();
    if (null == data || data.isEmpty) {
      throw CoseException(CoseErrorCode.cborDecodingError);
    }

    final element = data.first;
    if (element is! List) {
      throw CoseException(CoseErrorCode.unsupportedFormat);
    }

    List items = element;
    if (items.length != cborDataLength) {
      throw CoseException(CoseErrorCode.invalidFormat);
    }
    return items;
  }

  static Map<dynamic, dynamic> parseHeader(Uint8Buffer protectedHeader) {
    final headers = Cbor();
    headers.decodeFromBuffer(protectedHeader);
    final headerList = headers.getDecodedData();
    if (headerList == null || headerList is! List) {
      throw CoseException(CoseErrorCode.unsupportedHeaderFormat);
    }
    if (headerList.isEmpty) {
      throw CoseException(CoseErrorCode.cborDecodingError);
    }
    return headerList.first;
  }

  static Map<dynamic, dynamic> parsePayload(Uint8Buffer payloadBytes) {
    var payloadCbor = Cbor();
    payloadCbor.decodeFromBuffer(payloadBytes);

    try {
      var data = payloadCbor.getDecodedData();
      if (null == data) {
        throw CoseException(CoseErrorCode.payloadFormatError);
      }
      return data.first;
    } on Exception {
      throw CoseException(CoseErrorCode.payloadFormatError);
    }
  }

  static String parseKid(Map<dynamic, dynamic> header) {
    final kidBuffer = header[4];
    final kid = Uint8List.view(kidBuffer.buffer, 0, kidBuffer.length);
    return String.fromCharCodes(kid);
  }

  void verify(Map<String, dynamic> jwk) {
    PublicKey? publicKey = KeyPair.fromJwk(jwk).publicKey;

    if (publicKey == null) {
      throw CoseException(CoseErrorCode.invalidSignature);
    }

    final sigStructure = Cbor();
    final sigStructureEncoder = sigStructure.encoder;

    sigStructureEncoder.writeArray([
      'Signature1', // context string
      Uint8List.view(protectedHeader.buffer, 0,
          protectedHeader.length), // protected body (header)
      Uint8List(0),
      Uint8List.view(payloadBytes.buffer, 0, payloadBytes.length)
    ]);

    sigStructure.decodeFromInput();
    final sigStructureBytes = sigStructure.output.getData();

    bool verified = false;
    if (publicKey is! EcPublicKey || -7 != alg) {
      throw CoseException(CoseErrorCode.unsupportedAlgorithm);
    }

    Verifier verifier =
        publicKey.createVerifier(algorithms.signing.ecdsa.sha256);
    
    verified = verifier.verify(
        sigStructureBytes.buffer.asUint8List(),
        Signature(
            Uint8List.view(signers.buffer, 0, signers.length)));

    if (!verified) {
      throw CoseException(CoseErrorCode.invalidSignature);
    }
  }
}