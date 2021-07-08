import 'package:saiive.live/crypto/errors/TransactionError.dart';

class InsufficientBalanceError extends TransactionError {
  InsufficientBalanceError(String error, String txHex) : super(error: error, txHex: txHex);

  @override
  String copyText() {
    return error + " " + txHex;
  }
}
