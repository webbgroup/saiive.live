import 'dart:async';

import 'package:defichaindart/defichaindart.dart';
import 'package:saiive.live/crypto/chain.dart';
import 'package:saiive.live/crypto/database/wallet_database_factory.dart';
import 'package:saiive.live/crypto/model/wallet_account.dart';
import 'package:saiive.live/crypto/model/wallet_address.dart';
import 'package:saiive.live/crypto/wallet/address_type.dart';
import 'package:saiive.live/crypto/wallet/bitcoin_wallet.dart';
import 'package:saiive.live/crypto/wallet/defichain/defichain_wallet.dart';
import 'package:saiive.live/crypto/wallet/wallet-restore.dart';
import 'package:saiive.live/crypto/wallet/wallet.dart';
import 'package:saiive.live/network/account_history_service.dart';
import 'package:saiive.live/network/api_service.dart';
import 'package:saiive.live/network/model/account_history.dart';
import 'package:saiive.live/network/model/ivault.dart';
import 'package:saiive.live/service_locator.dart';
import 'package:flutter/foundation.dart';
import 'package:tuple/tuple.dart';
import 'package:saiive.live/network/model/transaction.dart' as tx;
import 'package:uuid/uuid.dart';

abstract class IWalletService {
  Future init();
  Future<bool> isRestoreNeeded();
  Future syncAll();

  Future<bool> hasAccounts();
  Future<List<WalletAccount>> getAccounts();
  Future<List<WalletAccount>> getAccountsForChain(ChainType chainType);

  Future<List<WalletAddress>> getAllPublicKeysFromAccount(WalletAccount account);
  Future<List<WalletAddress>> getPublicKeysFromAccount(WalletAccount account);
  Future<WalletAddress> getNextWalletAddress(WalletAccount walletAccount, bool isChangeAddress, AddressType addressType);

  Future<String> getPublicKey(ChainType chainType, AddressType addressType);
  Future<String> createAndSend(ChainType chainType, int amount, String token, String to, String retAddress,
      {bool waitForConfirmaton, StreamController<String> loadingStream, bool sendMax = false});
  Future<List<String>> getPublicKeys(ChainType chainType);

  Future<List<Tuple2<List<WalletAccount>, List<WalletAddress>>>> restore(ChainNet network);

  Future close();
  Future destroy();

  Future<WalletAccount> addAccount(WalletAccount account);
  Future<WalletAddress> updateAddress(WalletAddress account);
  Future<List<AccountHistory>> getAccountHistory(ChainType chain, String token, bool includeRewards);
  Future<List<tx.Transaction>> getTransactions(ChainType chain);

  Future<Map<String, bool>> getIsAlive();
  Future<String> getWifPrivateKey(WalletAccount account, WalletAddress address);

  Future<bool> validateAddress(WalletAccount account, WalletAddress address);
}

class WalletService implements IWalletService {
  BitcoinWallet _bitcoinWallet;
  DeFiChainWallet _defiWallet;

  List<IWallet> _wallets = List<IWallet>.empty(growable: true);

  @override
  Future init() async {
    _wallets.clear();
    _bitcoinWallet = sl.get<BitcoinWallet>();
    _defiWallet = sl.get<DeFiChainWallet>();

    _wallets.add(_bitcoinWallet);
    _wallets.add(_defiWallet);

    for (final wallet in _wallets) {
      await wallet.close();
    }

    await Future.wait([_bitcoinWallet.init(), _defiWallet.init()]);
  }

  Future<bool> isRestoreNeeded() async {
    var hasAnyoneMissingAccounts = false;
    for (var wallet in _wallets) {
      var hasAccounts = await wallet.hasAccounts();

      if (!hasAccounts) {
        hasAnyoneMissingAccounts = true;
        break;
      }
    }
    return hasAnyoneMissingAccounts;
  }

  @override
  Future close() async {
    _bitcoinWallet.close();
    _defiWallet.close();
  }

  @override
  Future<String> createAndSend(ChainType chainType, int amount, String token, String to, String retAddress,
      {bool waitForConfirmaton, StreamController<String> loadingStream, bool sendMax = false}) {
    if (chainType == ChainType.DeFiChain) {
      return _defiWallet.createAndSend(amount, token, to, waitForConfirmation: waitForConfirmaton, returnAddress: retAddress, loadingStream: loadingStream, sendMax: sendMax);
    }
    return _bitcoinWallet.createAndSend(amount, token, to, waitForConfirmation: waitForConfirmaton, returnAddress: retAddress, loadingStream: loadingStream, sendMax: sendMax);
  }

  @override
  Future<List<WalletAccount>> getAccounts() async {
    var defiAccounts = await _defiWallet.getAccounts();
    var btcAccounts = await _bitcoinWallet.getAccounts();

    var ret = List<WalletAccount>.from(defiAccounts);
    ret.addAll(btcAccounts);

    return ret;
  }

  @override
  Future<List<WalletAccount>> getAccountsForChain(ChainType chainType) {
    if (chainType == ChainType.DeFiChain) {
      return _defiWallet.getAccounts();
    }
    return _bitcoinWallet.getAccounts();
  }

  @override
  Future<WalletAddress> getNextWalletAddress(WalletAccount walletAccount, bool isChangeAddress, AddressType addressType) {
    if (walletAccount.chain == ChainType.DeFiChain) {
      return _defiWallet.getNextWalletAddress(walletAccount, addressType, isChangeAddress);
    }
    return _bitcoinWallet.getNextWalletAddress(walletAccount, addressType, isChangeAddress);
  }

  @override
  Future<String> getPublicKey(ChainType chainType, AddressType addressType) {
    if (chainType == ChainType.DeFiChain) {
      return _defiWallet.getPublicKey(false, addressType);
    }
    return _bitcoinWallet.getPublicKey(false, addressType);
  }

  @override
  Future<List<String>> getPublicKeys(ChainType chainType) {
    if (chainType == ChainType.DeFiChain) {
      return _defiWallet.getPublicKeys();
    }
    return _bitcoinWallet.getPublicKeys();
  }

  @override
  Future<List<WalletAddress>> getPublicKeysFromAccount(WalletAccount account) {
    if (account.chain == ChainType.DeFiChain) {
      return _defiWallet.getPublicKeysFromAccounts(account);
    }
    return _bitcoinWallet.getPublicKeysFromAccounts(account);
  }

  @override
  Future<List<WalletAddress>> getAllPublicKeysFromAccount(WalletAccount account) {
    if (account.chain == ChainType.DeFiChain) {
      return _defiWallet.getAllPublicKeysFromAccount(account);
    }
    return _bitcoinWallet.getAllPublicKeysFromAccount(account);
  }

  @override
  Future<bool> hasAccounts() async {
    var btcHasAccounts = await _bitcoinWallet.hasAccounts();
    var defiHasAccounts = await _defiWallet.hasAccounts();

    return btcHasAccounts && defiHasAccounts;
  }

  @override
  Future syncAll() async {
    await Future.wait([_defiWallet.syncAll(), _bitcoinWallet.syncAll()]);
  }

  @override
  Future<WalletAddress> updateAddress(WalletAddress address) {
    if (address.chain == ChainType.DeFiChain) {
      return _defiWallet.updateAddress(address);
    }
    return _bitcoinWallet.updateAddress(address);
  }

  @override
  Future<WalletAccount> addAccount(WalletAccount account) {
    if (account.chain == ChainType.DeFiChain) {
      return _defiWallet.addAccount(account);
    }
    return _bitcoinWallet.addAccount(account);
  }

  @override
  Future<List<Tuple2<List<WalletAccount>, List<WalletAddress>>>> restore(ChainNet network) {
    var bitcoinWallet = sl.get<BitcoinWallet>();
    var defiWallet = sl.get<DeFiChainWallet>();

    var restoreBtc = _restoreWallet(ChainType.Bitcoin, network, bitcoinWallet);
    var restoreDefi = _restoreWallet(ChainType.DeFiChain, network, defiWallet);

    return Future.wait([restoreBtc, restoreDefi]);
  }

  Future<List<AccountHistory>> getAccountHistory(ChainType chain, String token, bool includeRewards) async {
    if (chain == ChainType.DeFiChain) {
      var pubKeyList = await _defiWallet.getPublicKeys();
      return await sl.get<IAccountHistoryService>().getAddressesHistory('DFI', pubKeyList, token, !includeRewards);
    }
    return List<AccountHistory>.empty();
  }

  Future<List<tx.Transaction>> getTransactions(ChainType chain) async {
    if (chain == ChainType.DeFiChain) {
      var db = _defiWallet.getDatabase();
      return await db.getAllTransactions();
    }
    var db = _bitcoinWallet.getDatabase();
    return await db.getAllTransactions();
  }

  Future<String> getWifPrivateKey(WalletAccount walletAccount, WalletAddress address) async {
    ECPair privateKey;
    if (walletAccount.chain == ChainType.DeFiChain) {
      privateKey = await _defiWallet.getPrivateKey(address, walletAccount);
    } else {
      privateKey = await _bitcoinWallet.getPrivateKey(address, walletAccount);
    }
    return privateKey.toWIF();
  }

  Future<bool> validateAddress(WalletAccount walletAccount, WalletAddress address) async {
    if (walletAccount.chain == ChainType.DeFiChain) {
      return await _defiWallet.validateAddress(walletAccount, address);
    } else {
      return await _bitcoinWallet.validateAddress(walletAccount, address);
    }
  }

  Future<Tuple2<List<WalletAccount>, List<WalletAddress>>> _restoreWallet(ChainType chain, ChainNet network, IWallet wallet) async {
    var dataMap = Map();
    dataMap["chain"] = chain;
    dataMap["network"] = network;
    dataMap["seed"] = await sl.get<IVault>().getSeed();
    dataMap["password"] = ""; //await sl.get<Vault>().getSecret();
    dataMap["apiService"] = sl.get<ApiService>();
    var db = await sl.get<IWalletDatabaseFactory>().getDatabase(chain, network);

    await db.destroy();
    db = await sl.get<IWalletDatabaseFactory>().getDatabase(chain, network);

    var result = await compute(_searchAccounts, dataMap);

    for (var element in result.item1) {
      element.selected = true;
      await db.addOrUpdateAccount(element);
    }
    for (var address in result.item2) {
      await db.addAddress(address);
    }

    if (result.item1.length == 0) {
      final walletAccount = WalletAccount(Uuid().v4(),
          id: 0,
          chain: chain,
          account: 0,
          walletAccountType: WalletAccountType.HdAccount,
          derivationPathType: PathDerivationType.FullNodeWallet,
          name: ChainHelper.chainTypeString(chain),
          selected: true);

      await db.addOrUpdateAccount(walletAccount);

      await wallet.close();
      await wallet.init();

      var walletAddress = await wallet.getNextWalletAddress(walletAccount, AddressType.P2SHSegwit, false);
      walletAddress.name = ChainHelper.chainTypeString(chain);
      await db.addAddress(walletAddress);
    } else {
      var i = 0;
      for (var address in result.item2) {
        address.name = ChainHelper.chainTypeString(chain) + " " + i.toString();
        await db.addAddress(address);
        i++;
      }
    }

    await wallet.close();
    return result;
  }

  static Future<Tuple2<List<WalletAccount>, List<WalletAddress>>> _searchAccounts(Map dataMap) async {
    final ret = await WalletRestore.restore(
      dataMap["chain"],
      dataMap["network"],
      dataMap["seed"],
      dataMap["password"],
      dataMap["apiService"],
    );

    return ret;
  }

  @override
  Future destroy() async {
    await _bitcoinWallet.getDatabase().destroy();
    await _defiWallet.getDatabase().destroy();
  }

  @override
  Future<Map<String, bool>> getIsAlive() async {
    var ret = Map<String, bool>();

    for (final wallet in _wallets) {
      var isAlive = await wallet.isAlive();

      ret.putIfAbsent(wallet.walletType, () => isAlive);
    }

    return ret;
  }
}
