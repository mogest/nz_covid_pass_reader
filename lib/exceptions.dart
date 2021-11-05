class CovidPassException implements Exception {
  CovidPassErrorCode cause;
  CovidPassException(this.cause);
}

enum CovidPassErrorCode {
  invalidUrl,
  invalidIssuer,
  invalidFormat,
  missingPublicKey,
  expired,
  notYetValid,
  networkError,
}

class CoseException implements Exception {
  CoseErrorCode cause;
  CoseException(this.cause);
}

enum CoseErrorCode {
  cborDecodingError,
  unsupportedFormat,
  invalidFormat,
  unsupportedHeaderFormat,
  payloadFormatError,
  unsupportedAlgorithm,
  invalidSignature,
}