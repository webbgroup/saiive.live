import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saiive.live/appstate_container.dart';
import 'package:saiive.live/crypto/chain.dart';
import 'package:saiive.live/crypto/crypto/hd_wallet_util.dart';
import 'package:saiive.live/crypto/database/wallet_database.dart';
import 'package:saiive.live/crypto/database/wallet_database_factory.dart';
import 'package:saiive.live/crypto/model/wallet_account.dart';
import 'package:saiive.live/crypto/wallet/address_type.dart';
import 'package:saiive.live/generated/l10n.dart';
import 'package:saiive.live/helper/logger/LogHelper.dart';
import 'package:saiive.live/network/model/ivault.dart';
import 'package:saiive.live/service_locator.dart';
import 'package:saiive.live/ui/accounts/account_import_private_key_select_address_type_dialog.dart';
import 'package:saiive.live/ui/accounts/accounts_address_add_screen.dart';
import 'package:saiive.live/ui/accounts/accounts_edit_screen.dart';
import 'package:saiive.live/ui/utils/qr_code_scan.dart';
import 'package:saiive.live/util/sharedprefsutil.dart';
import 'package:uuid/uuid.dart';

class AccountsImportScreen extends StatefulWidget {
  final ChainType chainType;

  AccountsImportScreen(this.chainType);

  @override
  State<StatefulWidget> createState() => _AccountsImportScreen();
}

class _AccountsImportScreen extends State<AccountsImportScreen> {
  final _keyController = TextEditingController();

  @override
  initState() {
    super.initState();
  }

  popToAccountsPage() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<AddressType> selectPublicKeyTypeForPrivateKey() async {
    AddressType addressType = AddressType.P2SHSegwit;

    await showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return AccountImportPrivateKeySelectAddressTypeDialog(
            initialValue: addressType,
            onValueChange: (a) {
              addressType = a;
            });
      },
    );
    return addressType;
  }

  Future shouldImportPrivateKeyForPublicKey(String pubKey, String privKey, IWalletDatabase database) async {
    var walletAddress = await database.getWalletAddress(pubKey);
    var walletAccount = await database.getAccount(walletAddress.accountId);

    var import = ElevatedButton(
      child: Text(S.of(context).ok),
      onPressed: () async {
        try {
          walletAccount.walletAccountType = WalletAccountType.PrivateKey;
          await sl.get<IVault>().setPrivateKey(walletAccount.uniqueId, privKey);
          await database.addOrUpdateAccount(walletAccount);
        } finally {
          Navigator.of(context).pop();
        }
      },
    );
    var cancel = ElevatedButton(
      child: Text(S.of(context).cancel),
      onPressed: () {
        Navigator.of(context).pop();
      },
    );

    AlertDialog alert = AlertDialog(
      title: Text(S.of(context).wallet_accounts_import),
      content: Text(S.of(context).wallet_accounts_import_priv_key_for_pub_key(pubKey)),
      actions: [
        import,
        cancel,
      ],
    );
    await showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  Future onScan(String data) async {
    LogHelper.instance.d(data);

    data = data.trimLeft();
    data = data.trimRight();

    final currentNet = await sl.get<ISharedPrefsUtil>().getChainNetwork();
    final walletDbFactory = sl.get<IWalletDatabaseFactory>();
    final walletDb = await walletDbFactory.getDatabase(widget.chainType, currentNet);

    //propably a publicKey
    if (data.length == 34 || data.length == 42) {
      final isOwnAddress = await walletDb.isOwnAddress(data);

      if (isOwnAddress) {
        final walletAddress = await walletDb.getWalletAddress(data);

        final walletAccount = await walletDb.getAccount(walletAddress.accountId);

        if (walletAccount.walletAccountType == WalletAccountType.HdAccount) {
          await Navigator.of(context).push(MaterialPageRoute(builder: (BuildContext context) => AccountsAddressAddScreen(walletAccount, false, walletAddress: walletAddress)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(S.of(context).wallet_accounts_key_already_imported),
          ));
        }

        popToAccountsPage();

        return;
      }

      if (HdWalletUtil.isAddressValid(data, widget.chainType, currentNet)) {
        final walletAccount = WalletAccount(Uuid().v4(),
            id: -1,
            chain: widget.chainType,
            account: -1,
            selected: true,
            walletAccountType: WalletAccountType.PublicKey,
            derivationPathType: PathDerivationType.FullNodeWallet,
            name: ChainHelper.chainTypeString(widget.chainType) + "_" + data[data.length - 1]);

        var addressType = HdWalletUtil.getAddressType(data, widget.chainType, currentNet);

        await Navigator.of(context).push(MaterialPageRoute(
            settings: RouteSettings(name: "/accountsEditScreen"),
            builder: (BuildContext context) => AccountsEditScreen(walletAccount, currentNet, true, data, addressType, privateKey: null)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(S.of(context).wallet_accounts_import_invalid_pub_key),
        ));
        popToAccountsPage();
      }
    }
    //propably a privateKey
    else if (data.length == 52) {
      if (HdWalletUtil.isPrivateKeyValid(data, widget.chainType, currentNet)) {
        final walletAccount = WalletAccount(Uuid().v4(),
            id: -1,
            chain: widget.chainType,
            account: -1,
            selected: true,
            derivationPathType: PathDerivationType.SingleKey,
            walletAccountType: WalletAccountType.PrivateKey,
            name: ChainHelper.chainTypeString(widget.chainType) + "_" + data[data.length - 1]);

        var useAddressType = await selectPublicKeyTypeForPrivateKey();
        if (useAddressType == null) {
          return;
        }
        var address = HdWalletUtil.getPublicAddressFromWif(data, widget.chainType, currentNet, useAddressType);

        final isOwnAddress = await walletDb.isOwnAddress(address);

        if (isOwnAddress) {
          await shouldImportPrivateKeyForPublicKey(address, data, walletDb);
          popToAccountsPage();
        } else {
          Navigator.of(context).push(MaterialPageRoute(
              settings: RouteSettings(name: "/accountsEditScreen"),
              builder: (BuildContext context) => AccountsEditScreen(walletAccount, currentNet, true, address, AddressType.P2SHSegwit, privateKey: data)));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(S.of(context).wallet_accounts_import_invalid_priv_key),
        ));
        popToAccountsPage();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(S.of(context).wallet_accounts_import_invalid),
      ));
      popToAccountsPage();
    }
  }

  _buildAccountAddScreen(BuildContext context) {
    return Padding(
        padding: EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(S.of(context).wallet_accounts_import_info),
          SizedBox(height: 20),
          TextFormField(
            controller: _keyController,
            // The validator receives the text that the user has entered.
            validator: (value) {
              if (value == null || value.isEmpty) {
                return S.of(context).wallet_accounts_cannot_be_empty;
              }
              return null;
            },
            decoration: Platform.isMacOS
                ? InputDecoration(hintText: S.of(context).wallet_send_address)
                : InputDecoration(
                    hintText: S.of(context).wallet_send_address,
                    suffixIcon: IconButton(
                      onPressed: () async {
                        var status = await Permission.camera.status;
                        if (!status.isGranted) {
                          final permission = await Permission.camera.request();

                          if (!permission.isGranted) {
                            return;
                          }
                        }
                        final address = await Navigator.of(context).push(MaterialPageRoute(builder: (BuildContext context) => QrCodeScan()));
                        _keyController.text = address;
                      },
                      icon: Icon(Icons.camera_alt, color: StateContainer.of(context).curTheme.primary),
                    )),
          ),
          SizedBox(height: 20),
          Center(
              child: ElevatedButton(
                  child: Text(S.of(context).wallet_accounts_import),
                  onPressed: () async {
                    if (_keyController.text != null && _keyController.text.isNotEmpty) {
                      await onScan(_keyController.text);
                    }
                  }))
        ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          toolbarHeight: StateContainer.of(context).curTheme.toolbarHeight,
          title: Text(S.of(context).wallet_accounts_import),
          actions: [],
        ),
        body: _buildAccountAddScreen(context));
  }
}
