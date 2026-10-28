import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Banco local do Controle de Zoonoses. Funciona sem internet.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'controle_zoonoses.db');
    _database = await openDatabase(
      path,
      version: 3,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE agentes (nome TEXT PRIMARY KEY)''');
        await db.execute('''CREATE TABLE logradouros (nome TEXT PRIMARY KEY)''');
        await db.execute('''CREATE TABLE quadras (
          area TEXT NOT NULL, sc TEXT NOT NULL, quadra TEXT NOT NULL,
          PRIMARY KEY (area, sc, quadra))''');
        await db.execute('''CREATE TABLE quadra_logradouros (
          area TEXT NOT NULL, sc TEXT NOT NULL, quadra TEXT NOT NULL,
          rua TEXT NOT NULL, PRIMARY KEY (area, sc, quadra, rua))''');
        await db.execute('''CREATE TABLE imoveis (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          area TEXT NOT NULL, sc TEXT NOT NULL, quadra TEXT NOT NULL,
          rua TEXT NOT NULL, numero TEXT NOT NULL, tipo TEXT NOT NULL DEFAULT 'CS',
          UNIQUE(area, sc, quadra, rua, numero))''');
        await db.execute('''CREATE TABLE visitas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          area TEXT NOT NULL, sc TEXT NOT NULL, quadra TEXT NOT NULL,
          rua TEXT NOT NULL, numero TEXT NOT NULL, data_visita TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT '',
          UNIQUE(area, sc, quadra, rua, numero, data_visita))''');
        await db.execute('''CREATE TABLE recipientes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          area TEXT NOT NULL, sc TEXT NOT NULL, quadra TEXT NOT NULL,
          rua TEXT NOT NULL, numero TEXT NOT NULL, data_visita TEXT NOT NULL DEFAULT '',
          medida TEXT NOT NULL DEFAULT '', grupo TEXT NOT NULL DEFAULT '',
          tipo TEXT NOT NULL DEFAULT '', existente TEXT NOT NULL DEFAULT '',
          agua TEXT NOT NULL DEFAULT '', larva TEXT NOT NULL DEFAULT '')''');
        await db.execute('''CREATE TABLE demandas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          area TEXT NOT NULL, sc TEXT NOT NULL, quadra TEXT NOT NULL,
          rua TEXT NOT NULL, numero TEXT NOT NULL,
          demanda TEXT NOT NULL DEFAULT '', orientacao TEXT NOT NULL DEFAULT '',
          data_registro TEXT NOT NULL)''');
        await db.execute('''CREATE TABLE configuracoes (
          chave TEXT PRIMARY KEY, valor TEXT NOT NULL)''');
        await db.execute('''CREATE TABLE resultados_quadras (
          area TEXT NOT NULL, sc TEXT NOT NULL, quadra TEXT NOT NULL,
          data_visita TEXT NOT NULL, concluida INTEGER NOT NULL DEFAULT 0,
          pendencia INTEGER NOT NULL DEFAULT 0, larvas INTEGER NOT NULL DEFAULT 0,
          demanda INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (area, sc, quadra))''');
        await db.execute('''CREATE TABLE pendencias_imoveis (
          area TEXT NOT NULL, sc TEXT NOT NULL, quadra TEXT NOT NULL,
          rua TEXT NOT NULL, numero TEXT NOT NULL, data_visita TEXT NOT NULL,
          status TEXT NOT NULL,
          PRIMARY KEY (area, sc, quadra, rua, numero, data_visita))''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''CREATE TABLE resultados_quadras (
            area TEXT NOT NULL, sc TEXT NOT NULL, quadra TEXT NOT NULL,
            data_visita TEXT NOT NULL, concluida INTEGER NOT NULL DEFAULT 0,
            pendencia INTEGER NOT NULL DEFAULT 0, larvas INTEGER NOT NULL DEFAULT 0,
            demanda INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (area, sc, quadra))''');
        }
        if (oldVersion < 3) {
          await db.execute('''CREATE TABLE pendencias_imoveis (
            area TEXT NOT NULL, sc TEXT NOT NULL, quadra TEXT NOT NULL,
            rua TEXT NOT NULL, numero TEXT NOT NULL, data_visita TEXT NOT NULL,
            status TEXT NOT NULL,
            PRIMARY KEY (area, sc, quadra, rua, numero, data_visita))''');
        }
      },
    );
    return _database!;
  }

  Future<void> substituirLista(String tabela, String coluna, List<String> valores) async {
    const permitidas = {'agentes', 'logradouros'};
    if (!permitidas.contains(tabela) || coluna != 'nome') {
      throw ArgumentError('Lista de importação inválida.');
    }
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(tabela);
      final batch = txn.batch();
      for (final valor in valores.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()) {
        batch.insert(tabela, {coluna: valor}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<String>> carregarLista(String tabela) async {
    if (!{'agentes', 'logradouros'}.contains(tabela)) throw ArgumentError('Tabela inválida.');
    final db = await database;
    final rows = await db.query(tabela, orderBy: 'nome COLLATE NOCASE');
    return rows.map((r) => r['nome'] as String).toList();
  }

  Future<void> substituirQuadras(List<Map<String, String>> quadras) async {
    final db = await database;
    await db.transaction((txn) async {
      // Apenas atualiza a relação geográfica; não toca nos imóveis ou visitas.
      await txn.delete('quadras');
      final batch = txn.batch();
      for (final q in quadras) {
        batch.insert('quadras', {
          'area': q['area'] ?? '', 'sc': q['sc'] ?? '', 'quadra': q['quadra'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, String>>> carregarQuadras() async {
    final db = await database;
    final rows = await db.query('quadras', orderBy: 'area, sc, quadra');
    return rows.map((r) => r.map((k, v) => MapEntry(k, v.toString()))).toList();
  }

  Future<void> salvarRuaNaQuadra({required String area, required String sc, required String quadra, required String rua}) async {
    final db = await database;
    await db.insert('quadra_logradouros', {'area': area, 'sc': sc, 'quadra': quadra, 'rua': rua}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<String>> carregarRuasDaQuadra({required String area, required String sc, required String quadra}) async {
    final db = await database;
    final rows = await db.query('quadra_logradouros', where: 'area=? AND sc=? AND quadra=?', whereArgs: [area, sc, quadra], orderBy: 'rua COLLATE NOCASE');
    return rows.map((r) => r['rua'] as String).toList();
  }

  Future<List<Map<String, String>>> carregarImoveis({required String area, required String sc, required String quadra}) async {
    final db = await database;
    final rows = await db.rawQuery('''SELECT i.area, i.sc, i.quadra, i.rua, i.numero, i.tipo,
      COALESCE(v.status, '') AS status, COALESCE(v.data_visita, '') AS data_visita
      FROM imoveis i LEFT JOIN visitas v ON v.id = (
        SELECT v2.id FROM visitas v2 WHERE v2.area=i.area AND v2.sc=i.sc AND v2.quadra=i.quadra
        AND v2.rua=i.rua AND v2.numero=i.numero ORDER BY v2.data_visita DESC, v2.id DESC LIMIT 1)
      WHERE i.area=? AND i.sc=? AND i.quadra=? ORDER BY i.rua COLLATE NOCASE, i.numero''', [area, sc, quadra]);
    return rows.map((r) => r.map((k, v) => MapEntry(k, v.toString()))).toList();
  }

  Future<void> salvarImovel({required String area, required String sc, required String quadra, required String rua, required String numero, required String tipo, required String status, required String dataVisita}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('imoveis', {
        'area': area, 'sc': sc, 'quadra': quadra, 'rua': rua, 'numero': numero,
        'tipo': tipo.isEmpty ? 'CS' : tipo,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('visitas', {
        'area': area, 'sc': sc, 'quadra': quadra, 'rua': rua, 'numero': numero,
        'data_visita': dataVisita, 'status': status,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> atualizarTipoImovel({required String area, required String sc, required String quadra, required String rua, required String numero, required String tipo}) async {
    final db = await database;
    await db.update('imoveis', {'tipo': tipo.isEmpty ? 'CS' : tipo},
      where: 'area=? AND sc=? AND quadra=? AND rua=? AND numero=?',
      whereArgs: [area, sc, quadra, rua, numero]);
  }

  Future<List<Map<String, String>>> carregarRecipientes({required String area, required String sc, required String quadra, required String rua, required String numero, required String dataVisita}) async {
    final db = await database;
    final rows = await db.query('recipientes', where: 'area=? AND sc=? AND quadra=? AND rua=? AND numero=? AND data_visita=?', whereArgs: [area, sc, quadra, rua, numero, dataVisita], orderBy: 'id');
    return rows.map((r) => r.map((k, v) => MapEntry(k, v.toString()))..remove('id')).toList();
  }

  Future<void> salvarRecipientes({required String area, required String sc, required String quadra, required String rua, required String numero, required String dataVisita, required List<Map<String, String>> recipientes}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('recipientes', where: 'area=? AND sc=? AND quadra=? AND rua=? AND numero=? AND data_visita=?', whereArgs: [area, sc, quadra, rua, numero, dataVisita]);
      final batch = txn.batch();
      for (final r in recipientes) {
        batch.insert('recipientes', {
          'area': area, 'sc': sc, 'quadra': quadra, 'rua': rua, 'numero': numero,
          'data_visita': dataVisita,
          'medida': r['medida'] ?? '', 'grupo': r['grupo'] ?? '', 'tipo': r['tipo'] ?? '',
          'existente': r['existente'] ?? '', 'agua': r['agua'] ?? '', 'larva': r['larva'] ?? '',
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// Registra o resultado final da vistoria sem apagar os dados históricos.
  Future<Map<String, bool>> finalizarVistoriaQuadra({
    required String area,
    required String sc,
    required String quadra,
    required String dataVisita,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final visitas = await txn.query(
        'visitas', columns: ['status'],
        where: 'area=? AND sc=? AND quadra=? AND data_visita=?',
        whereArgs: [area, sc, quadra, dataVisita],
      );
      final temImoveis = visitas.isNotEmpty;
      final todosTrabalhados = temImoveis && visitas.every((r) => (r['status'] ?? '') == 'T');
      final temPendencia = visitas.any((r) => (r['status'] ?? '') != 'T');
      await txn.delete('pendencias_imoveis',
        where: 'area=? AND sc=? AND quadra=? AND data_visita=?',
        whereArgs: [area, sc, quadra, dataVisita]);
      final imoveisPendentes = await txn.query('visitas',
        columns: ['rua', 'numero', 'status'],
        where: 'area=? AND sc=? AND quadra=? AND data_visita=? AND status<>?',
        whereArgs: [area, sc, quadra, dataVisita, 'T']);
      final pendenciasBatch = txn.batch();
      for (final imovel in imoveisPendentes) {
        pendenciasBatch.insert('pendencias_imoveis', {
          'area': area, 'sc': sc, 'quadra': quadra,
          'rua': imovel['rua'], 'numero': imovel['numero'],
          'data_visita': dataVisita, 'status': imovel['status'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await pendenciasBatch.commit(noResult: true);

      final recipientes = await txn.rawQuery("""
        SELECT COUNT(*) AS total FROM recipientes
        WHERE area=? AND sc=? AND quadra=? AND data_visita=?
          AND CAST(TRIM(larva) AS INTEGER) > 0
      """, [area, sc, quadra, dataVisita]);
      final temLarvas = ((recipientes.first['total'] as int?) ?? 0) > 0;

      final demandas = await txn.rawQuery("""
        SELECT COUNT(*) AS total FROM demandas
        WHERE area=? AND sc=? AND quadra=?
          AND (TRIM(demanda) <> '' OR TRIM(orientacao) <> '')
      """, [area, sc, quadra]);
      final temDemanda = ((demandas.first['total'] as int?) ?? 0) > 0;

      await txn.insert('resultados_quadras', {
        'area': area, 'sc': sc, 'quadra': quadra, 'data_visita': dataVisita,
        'concluida': todosTrabalhados ? 1 : 0,
        'pendencia': temPendencia ? 1 : 0,
        'larvas': temLarvas ? 1 : 0,
        'demanda': temDemanda ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      return {'concluida': todosTrabalhados, 'pendencia': temPendencia,
        'larvas': temLarvas, 'demanda': temDemanda};
    });
  }

  Future<List<Map<String, String>>> carregarPendenciasQuadra({
    required String area,
    required String sc,
    required String quadra,
    required String dataVisita,
  }) async {
    final db = await database;
    final rows = await db.query('pendencias_imoveis',
      where: 'area=? AND sc=? AND quadra=? AND data_visita=?',
      whereArgs: [area, sc, quadra, dataVisita],
      orderBy: 'rua COLLATE NOCASE, numero');
    return rows.map((row) => row.map((key, value) => MapEntry(key, value.toString()))).toList();
  }

  Future<Map<String, Map<String, bool>>> carregarResultadosQuadras() async {
    final db = await database;
    final rows = await db.query('resultados_quadras');
    final resultados = <String, Map<String, bool>>{};
    for (final row in rows) {
      final chave = '${row['area']}|${row['sc']}|${row['quadra']}';
      resultados[chave] = {
        'concluida': row['concluida'] == 1, 'pendencia': row['pendencia'] == 1,
        'larvas': row['larvas'] == 1, 'demanda': row['demanda'] == 1,
      };
    }
    return resultados;
  }

  Future<void> salvarConfiguracao(String chave, String valor) async {
    final db = await database;
    await db.insert('configuracoes', {'chave': chave, 'valor': valor}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> carregarConfiguracao(String chave) async {
    final db = await database;
    final rows = await db.query('configuracoes', where: 'chave=?', whereArgs: [chave], limit: 1);
    return rows.isEmpty ? null : rows.first['valor'] as String?;
  }

  Future<Map<String, String>?> carregarUltimaDemanda({required String area, required String sc, required String quadra, required String rua, required String numero}) async {
    final db = await database;
    final rows = await db.query('demandas', where: 'area=? AND sc=? AND quadra=? AND rua=? AND numero=?', whereArgs: [area, sc, quadra, rua, numero], orderBy: 'id DESC', limit: 1);
    if (rows.isEmpty) return null;
    return {'demanda': '${rows.first['demanda'] ?? ''}', 'orientacao': '${rows.first['orientacao'] ?? ''}'};
  }

  Future<void> salvarDemanda({required String area, required String sc, required String quadra, required String rua, required String numero, required String demanda, required String orientacao}) async {
    final db = await database;
    await db.insert('demandas', {
      'area': area, 'sc': sc, 'quadra': quadra, 'rua': rua, 'numero': numero,
      'demanda': demanda, 'orientacao': orientacao, 'data_registro': DateTime.now().toIso8601String(),
    });
  }

  /// Exporta todas as tabelas para JSON, para backup portátil.
  Future<String> exportarBackupJson() async {
    final db = await database;
    final nomes = ['agentes', 'logradouros', 'quadras', 'quadra_logradouros', 'imoveis', 'visitas', 'recipientes', 'demandas', 'configuracoes', 'resultados_quadras', 'pendencias_imoveis'];
    final dados = <String, dynamic>{'app': 'controle_zoonoses', 'versao': 3, 'exportadoEm': DateTime.now().toIso8601String(), 'tabelas': <String, dynamic>{}};
    for (final nome in nomes) {
      dados['tabelas'][nome] = await db.query(nome);
    }
    return const JsonEncoder.withIndent('  ').convert(dados);
  }

  /// Restaura backup em transação. Não aceita arquivo de outra aplicação.
  Future<void> restaurarBackupJson(String conteudo) async {
    final json = jsonDecode(conteudo);
    if (json is! Map || json['app'] != 'controle_zoonoses' || !{1, 2, 3}.contains(json['versao']) || json['tabelas'] is! Map) {
      throw const FormatException('Arquivo de backup inválido ou incompatível.');
    }
    final tabelas = json['tabelas'] as Map;
    final permitidas = ['agentes', 'logradouros', 'quadras', 'quadra_logradouros', 'imoveis', 'visitas', 'recipientes', 'demandas', 'configuracoes', 'resultados_quadras', 'pendencias_imoveis'];
    final db = await database;
    await db.transaction((txn) async {
      for (final tabela in permitidas.reversed) { await txn.delete(tabela); }
      for (final tabela in permitidas) {
        final linhas = tabelas[tabela];
        if (linhas is! List) continue;
        for (final linha in linhas) {
          if (linha is Map) {
            await txn.insert(tabela, Map<String, Object?>.from(linha), conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
    });
  }

  Future<String> caminhoBanco() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'controle_zoonoses.db');
  }
}
