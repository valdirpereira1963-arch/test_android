import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlng;
import 'database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const MinhaAplicacao());
}

class MinhaAplicacao extends StatelessWidget {
  const MinhaAplicacao({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Controle de Zoonoses',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const TelaAbertura(),
    );
  }
}

class TelaAbertura extends StatefulWidget {
  const TelaAbertura({super.key});

  @override
  State<TelaAbertura> createState() => _TelaAberturaState();
}

class _TelaAberturaState extends State<TelaAbertura> {
  List<String> _agentes = [];
  String? _agenteSelecionado;
  List<String> _logradouros = [];
  List<String> _demandasDisponiveis = [];
  String? _logradouroSelecionado;
  List<String> _quadrasKml = [];
  List<Map<String, String>> _relacaoQuadras = [];
  List<Map<String, dynamic>> _poligonosKml = [];
  Map<String, Map<String, bool>> _resultadosQuadras = {};
  String? _areaSelecionada;
  String? _scSelecionado;
  String? _quadraSelecionada;
  String? _operacaoSelecionada;

  final fmap.LayerHitNotifier<String> _quadraHitNotifier =
    ValueNotifier<fmap.LayerHitResult<String>?>(null);

Map<String, String>? _buscarQuadra(String quadra) {
  String normalizarQuadra(String valor) {
    final texto = valor.trim();

    final numero = int.tryParse(texto);

    if (numero != null) {
      return numero.toString();
    }

    return texto;
  }

  final quadraNormalizada = normalizarQuadra(quadra);

  for (final registro in _relacaoQuadras) {
    final quadraTabela =
        normalizarQuadra(registro['quadra'] ?? '');

    if (quadraTabela == quadraNormalizada) {
      return registro;
    }
  }

  return null;
}

@override
void initState() {
  super.initState();
  _carregarDadosPersistidos();

  _quadraHitNotifier.addListener(() {
    final resultado = _quadraHitNotifier.value;

    if (resultado != null && resultado.hitValues.isNotEmpty) {
      final quadra = resultado.hitValues.first;

      final registro = _buscarQuadra(quadra);

      if (registro != null) {
        setState(() {
          _quadraSelecionada = registro['quadra'];
          _scSelecionado = registro['sc'];
          _areaSelecionada = registro['area'];
        });

        debugPrint(
          'QUADRA: ${registro['quadra']} | '
          'S.C.: ${registro['sc']} | '
          'ÁREA: ${registro['area']}',
        );
      } else {
        debugPrint(
          'QUADRA $quadra NÃO ENCONTRADA NA TABELA',
        );
      }
    }
  });
}


Future<void> _carregarDadosPersistidos() async {
  final db = DatabaseHelper.instance;
  final agentes = await db.carregarLista('agentes');
  final logradouros = await db.carregarLista('logradouros');
  final quadras = await db.carregarQuadras();
  final demandasJson = await db.carregarConfiguracao('demandas_disponiveis');
  final resultados = await db.carregarResultadosQuadras();
  List<String> demandas = [];
  if (demandasJson != null) {
    try {
      demandas = (jsonDecode(demandasJson) as List).map((e) => e.toString()).toList();
    } catch (_) {}
  }
  if (!mounted) return;
  setState(() {
    _agentes = agentes;
    _logradouros = logradouros;
    _demandasDisponiveis = demandas;
    _relacaoQuadras = quadras;
    _resultadosQuadras = resultados;
    if (_agenteSelecionado != null && !_agentes.contains(_agenteSelecionado)) {
      _agenteSelecionado = null;
    }
  });
}

latlng.LatLng _melhorPontoDentroDaQuadra(
  List<Map<String, double>> pontos,
) {
  if (pontos.isEmpty) {
    return const latlng.LatLng(-22.555, -44.960);
  }

  // Limites do polígono
  double minLat = pontos.first['latitude']!;
  double maxLat = pontos.first['latitude']!;
  double minLon = pontos.first['longitude']!;
  double maxLon = pontos.first['longitude']!;

  for (final ponto in pontos) {
    final lat = ponto['latitude']!;
    final lon = ponto['longitude']!;

    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lon < minLon) minLon = lon;
    if (lon > maxLon) maxLon = lon;
  }

  // Verifica se um ponto está dentro do polígono
  bool estaDentro(double lat, double lon) {
    bool dentro = false;

    for (int i = 0, j = pontos.length - 1;
        i < pontos.length;
        j = i++) {
      final lati = pontos[i]['latitude']!;
      final loni = pontos[i]['longitude']!;
      final latj = pontos[j]['latitude']!;
      final lonj = pontos[j]['longitude']!;

      final cruza = ((lati > lat) != (latj > lat)) &&
          (lon <
              (lonj - loni) *
                      (lat - lati) /
                      (latj - lati) +
                  loni);

      if (cruza) {
        dentro = !dentro;
      }
    }

    return dentro;
  }

  // Distância aproximada de um ponto até um segmento
  double distanciaSegmento(
    double px,
    double py,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;

    if (dx == 0 && dy == 0) {
      final ex = px - x1;
      final ey = py - y1;
      return ex * ex + ey * ey;
    }

    final t =
        ((px - x1) * dx + (py - y1) * dy) /
            (dx * dx + dy * dy);

    final tc = t.clamp(0.0, 1.0);

    final cx = x1 + tc * dx;
    final cy = y1 + tc * dy;

    final ex = px - cx;
    final ey = py - cy;

    return ex * ex + ey * ey;
  }

  // Distância mínima até as bordas da quadra
  double distanciaDasBordas(double lat, double lon) {
    double menor = double.infinity;

    for (int i = 0; i < pontos.length; i++) {
      final atual = pontos[i];
      final proximo = pontos[(i + 1) % pontos.length];

      final distancia = distanciaSegmento(
        lon,
        lat,
        atual['longitude']!,
        atual['latitude']!,
        proximo['longitude']!,
        proximo['latitude']!,
      );

      if (distancia < menor) {
        menor = distancia;
      }
    }

    return menor;
  }

  // Primeiro tenta o centro da caixa
  final centroLat = (minLat + maxLat) / 2;
  final centroLon = (minLon + maxLon) / 2;

  if (estaDentro(centroLat, centroLon)) {
    return latlng.LatLng(centroLat, centroLon);
  }

  // Procura o melhor ponto interno.
  // Quanto maior a distância das bordas, melhor o ponto para o número.
  double melhorLat = centroLat;
  double melhorLon = centroLon;
  double melhorDistancia = -1;

  const divisao = 30;

  for (int y = 0; y <= divisao; y++) {
    final lat =
        minLat + (maxLat - minLat) * y / divisao;

    for (int x = 0; x <= divisao; x++) {
      final lon =
          minLon + (maxLon - minLon) * x / divisao;

      if (estaDentro(lat, lon)) {
        final distancia =
            distanciaDasBordas(lat, lon);

        if (distancia > melhorDistancia) {
          melhorDistancia = distancia;
          melhorLat = lat;
          melhorLon = lon;
        }
      }
    }
  }

  return latlng.LatLng(
    melhorLat,
    melhorLon,
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: const Text(
          'CONTROLE DE ZOONOSES',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Dados e backup',
            icon: const Icon(Icons.storage),
            onSelected: (acao) async {
              try {
                if (acao == 'backup') {
                  final json = await DatabaseHelper.instance.exportarBackupJson();
                  final caminho = await FilePicker.platform.saveFile(
                    dialogTitle: 'Salvar cópia de segurança',
                    fileName: 'backup_controle_zoonoses.json',
                    type: FileType.custom,
                    allowedExtensions: ['json'],
                    bytes: Uint8List.fromList(utf8.encode(json)),
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(caminho == null ? 'Backup cancelado.' : 'Backup salvo com sucesso.'),
                  ));
                } else if (acao == 'restaurar') {
                  final arquivo = await FilePicker.pickFile(
                    type: FileType.custom,
                    allowedExtensions: ['json'],
                  );
                  if (arquivo == null) return;
                  final conteudo = utf8.decode(await arquivo.readAsBytes());
                  await DatabaseHelper.instance.restaurarBackupJson(conteudo);
                  await _carregarDadosPersistidos();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Backup restaurado. Os dados locais foram substituídos pelo conteúdo do backup.'),
                  ));
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha na operação de dados: $e')));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'backup', child: Text('Fazer backup dos dados')),
              PopupMenuItem(value: 'restaurar', child: Text('Restaurar backup JSON')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 55),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ======================================================
              // ÁREA PRINCIPAL
              // ======================================================
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    // CIDADE / AGENTE
                    SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          Expanded(
                            child: _campo(
                              'Cidade, Estado',
                              Icons.location_city,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _agenteSelecionado,
                              decoration: const InputDecoration(
                                labelText: 'Agente',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                              ),
                              items: _agentes.map((agente) {
                                return DropdownMenuItem<String>(
                                  value: agente,
                                  child: Text(
                                    agente,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: _agentes.isEmpty
                                  ? null
                                  : (valor) {
                                      setState(() {
                                        _agenteSelecionado = valor;
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 5),

                    // OPERAÇÃO
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'OPERAÇÃO',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 3),

                    SizedBox(
                      height: 52,
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Selecione a operação',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Visita a Imóveis',
                            child: Text('Visita a Imóveis'),
                          ),
                          DropdownMenuItem(
                            value: 'Controle de Criadouros',
                            child: Text('Controle de Criadouros'),
                          ),
                          DropdownMenuItem(
                            value: 'Nebulização',
                            child: Text('Nebulização'),
                          ),
                          DropdownMenuItem(value: 'ADL', child: Text('ADL')),
                          DropdownMenuItem(
                            value: 'Pendência',
                            child: Text('Pendência'),
                          ),
                          DropdownMenuItem(
                            value: 'Demandas',
                            child: Text('Demandas'),
                          ),
                          DropdownMenuItem(
                            value: 'Obras',
                            child: Text('Obras'),
                          ),
                        ],
                        onChanged: (valor) {
                          setState(() {
                            _operacaoSelecionada = valor;
                          });
                        },
                      ),
                    ),

                    const SizedBox(height: 6),

                    // ÁREA / S.C. / QUADRA
                    SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: _campo(
                              _areaSelecionada ?? 'ÁREA',
                              Icons.map,
                            ),
                          ),

                          const SizedBox(width: 6),

                          Expanded(
                            flex: 2,
                            child: _campo(
                              _scSelecionado ?? 'S.C.',
                              Icons.grid_view,
                            ),
                          ),

                          const SizedBox(width: 6),

                          Expanded(
                            flex: 2,
                            child: _campo(
                              _quadraSelecionada ?? 'QUADRA',
                              Icons.crop_square,
                            ),
                          ),

                          const SizedBox(width: 8),

                          SizedBox(
                            width: 105,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () async {
                                if (_quadraSelecionada == null ||
                                    _areaSelecionada == null ||
                                    _scSelecionado == null ||
                                    _operacaoSelecionada == null) {
                                  return;
                                }

                                debugPrint(
                                  'OPERAÇÃO CONFIRMADA: '
                                  'OPERAÇÃO=$_operacaoSelecionada '
                                  'ÁREA=$_areaSelecionada '
                                  'S.C.=$_scSelecionado '
                                  'QUADRA=$_quadraSelecionada',
                                );

                                if (_operacaoSelecionada ==
                                    'Visita a Imóveis') {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TelaVisitaImoveis(
                                        area: _areaSelecionada!,
                                        sc: _scSelecionado!,
                                        quadra: _quadraSelecionada!,
                                        logradouros: _logradouros,
                                      ),
                                    ),
                                  );
                                  await _carregarDadosPersistidos();
                                }
                              },

                              child: const Text(
                                'CONFIRMAR',
                                style: TextStyle(fontSize: 9),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          SizedBox(
                            width: 115,
                            height: 52,
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _areaSelecionada = null;
                                  _scSelecionado = null;
                                  _quadraSelecionada = null;
                                });
                              },
                              child: const Text(
                                'CANCELAR',
                                style: TextStyle(fontSize: 9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 7),

                    // ==================================================
                    // MAPA
                    // ==================================================
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 1.5),
                          borderRadius: BorderRadius.circular(7),
                        ),

                        child: fmap.FlutterMap(
                          options: const fmap.MapOptions(
                            initialCenter: latlng.LatLng(-22.555, -44.960),
                            initialZoom: 14,
                          ),
                         children: [
                            fmap.TileLayer(
                              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                            ),

                            if (_poligonosKml.isNotEmpty)
                              fmap.PolygonLayer<String>(
                                hitNotifier: _quadraHitNotifier,
                                polygons: _poligonosKml.map((poligono) {
                                  final coordenadas =
                                      poligono['coordenadas']
                                          as List<Map<String, double>>;

                                  final pontos = coordenadas.map((ponto) {
                                    return latlng.LatLng(
                                      ponto['latitude']!,
                                      ponto['longitude']!,
                                    );
                                  }).toList();

                                  final nomeQuadra = poligono['quadra'] as String;
                                  final relacao = _buscarQuadra(nomeQuadra);
                                  final areaMapa = relacao?['area'] ?? _areaSelecionada ?? '';
                                  final scMapa = relacao?['sc'] ?? _scSelecionado ?? '';
                                  final chaveResultado = '$areaMapa|$scMapa|$nomeQuadra';
                                  final resultado = _resultadosQuadras[chaveResultado];
                                  var corPreenchimento = Colors.transparent;
                                  var corContorno = Colors.green;
                                  if (_operacaoSelecionada == 'Visita a Imóveis') {
                                    if (resultado?['larvas'] == true) {
                                      corPreenchimento = Colors.red.withOpacity(0.38);
                                      corContorno = Colors.red;
                                    } else if (resultado?['concluida'] == true) {
                                      corPreenchimento = Colors.green.withOpacity(0.32);
                                      corContorno = Colors.green;
                                    }
                                  } else if (_operacaoSelecionada == 'Pendência' && resultado?['pendencia'] == true) {
                                    corPreenchimento = Colors.orange.withOpacity(0.42);
                                    corContorno = Colors.deepOrange;
                                  } else if (_operacaoSelecionada == 'Demandas' && resultado?['demanda'] == true) {
                                    corPreenchimento = Colors.blue.withOpacity(0.38);
                                    corContorno = Colors.blue;
                                  }
                                  return fmap.Polygon<String>(
                                    points: pontos,
                                    hitValue: nomeQuadra,
                                    color: corPreenchimento,
                                    borderColor: corContorno,
                                    borderStrokeWidth: 2,
                                  );
                                }).toList(),
                              ),

                            fmap.MarkerLayer(
                              markers: _poligonosKml.map((poligono) {
                                final coordenadas =
                                    poligono['coordenadas']
                                        as List<Map<String, double>>;

                                final pontoNumero = _melhorPontoDentroDaQuadra(
                                  coordenadas,
                                );

                                return fmap.Marker(
                                  point: pontoNumero,
                                  width: 60,
                                  height: 30,
                                  child: Center(
                                    child: Text(
                                      poligono['quadra'] as String,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // ======================================================
              // COLUNA DIREITA
              // ======================================================
              SizedBox(
                width: 300,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'IMPORTAÇÃO',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    _botaoImportacao('Agentes', Icons.people),

                    _botaoImportacao('Logradouros', Icons.streetview),

                    _botaoImportacao('Quadras', Icons.grid_on),

                    _botaoImportacao('Mapa KML', Icons.map),

                    _botaoImportacao('ADL', Icons.analytics),

                    _botaoImportacao('Bloqueio', Icons.block),

                    _botaoImportacao(
                      'Demandas / Reclamações',
                      Icons.assignment,
                    ),

                    const Spacer(),

                    // ==================================================
                    // INDICADORES
                    // ==================================================
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 5,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: const [
                                Text(
                                  '% CONCLUÍDA',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '0%',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 38, color: Colors.grey),
                          Expanded(
                            child: Column(
                              children: const [
                                Text(
                                  '% LARVAS',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '0%',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 6),

                    // ==================================================
                    // NOVO CICLO
                    // ==================================================
                    SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.refresh),
                        label: const Text(
                          'NOVO CICLO',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // CAMPO
  // ================================================================
  static Widget _campo(String titulo, IconData icone) {
    return TextFormField(
      decoration: InputDecoration(
        labelText: titulo,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icone),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
  }

  // ================================================================
  // BOTÃO DE IMPORTAÇÃO
  // ================================================================
  Widget _botaoImportacao(String titulo, IconData icone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: SizedBox(
        height: 39,
        child: OutlinedButton.icon(
          onPressed: () async {
            debugPrint('BOTAO DE IMPORTACAO: $titulo');

            // ======================================================
            // AGENTES
            // ======================================================
            if (titulo == 'Agentes') {
              final arquivo = await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: ['txt'],
              );

              if (arquivo != null) {
                final bytes = await arquivo.readAsBytes();
                final conteudo = utf8.decode(bytes);

                final agentes = conteudo
                    .split(RegExp(r'\r?\n'))
                    .map((linha) => linha.trim())
                    .where((linha) => linha.isNotEmpty)
                    .toList();

                await DatabaseHelper.instance.substituirLista('agentes', 'nome', agentes);
                setState(() {
                  _agentes = agentes;
                  _agenteSelecionado = null;
                });

                debugPrint('Arquivo de agentes: ${arquivo.name}');
                debugPrint('Agentes encontrados: ${agentes.length}');
              }

              // ======================================================
              // LOGRADOUROS
              // ======================================================
            } else if (titulo == 'Logradouros') {
              final arquivo = await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: ['txt'],
              );

              if (arquivo != null) {
                final bytes = await arquivo.readAsBytes();
                final conteudo = utf8.decode(bytes);

                final logradouros = conteudo
                    .split(RegExp(r'\r?\n'))
                    .map((linha) => linha.trim())
                    .where((linha) => linha.isNotEmpty)
                    .toList();

                await DatabaseHelper.instance.substituirLista('logradouros', 'nome', logradouros);
                setState(() {
                  _logradouros = logradouros;
                  _logradouroSelecionado = null;
                });

                debugPrint('Arquivo de logradouros: ${arquivo.name}');
                debugPrint('Logradouros encontrados: ${logradouros.length}');
              }

              // ======================================================
              // DEMANDAS / RECLAMAÇÕES
              // ======================================================
            } else if (titulo == 'Demandas / Reclamações') {
              final arquivo = await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: ['txt'],
              );
              if (arquivo != null) {
                final conteudo = utf8.decode(await arquivo.readAsBytes());
                final demandas = conteudo.split(RegExp(r'\r?\n'))
                    .map((linha) => linha.trim())
                    .where((linha) => linha.isNotEmpty).toSet().toList();
                await DatabaseHelper.instance.salvarConfiguracao(
                  'demandas_disponiveis', jsonEncode(demandas));
                if (!mounted) return;
                setState(() { _demandasDisponiveis = demandas; });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${demandas.length} demandas importadas e salvas.'),
                ));
              }

              // ======================================================
              // MAPA KML
              // ======================================================
            } else if (titulo == 'Mapa KML') {
              debugPrint('ENTROU NO MAPA KML');

              final arquivos = await FilePicker.pickFiles(type: FileType.any);

              if (arquivos.isEmpty) {
                debugPrint('NENHUM ARQUIVO KML SELECIONADO');
                return;
              }

              final arquivo = arquivos.first;

              debugPrint('ARQUIVO SELECIONADO: ${arquivo.name}');

              final bytes = await arquivo.readAsBytes();
              final conteudo = utf8.decode(bytes);

              final documento = XmlDocument.parse(conteudo);

              final placemarks = documento.findAllElements('Placemark');

              debugPrint('KML importado: ${arquivo.name}');
              debugPrint('Quantidade de quadras: ${placemarks.length}');

              final quadras = <String>[];

              final poligonos = <Map<String, dynamic>>[];

              for (final placemark in placemarks) {
                debugPrint('TESTANDO PLACEMARK');
                debugPrint(placemark.toXmlString());

                final nome = placemark
                    .findElements('name')
                    .firstOrNull
                    ?.innerText
                    .trim();
                final coordenadasTexto = placemark
                    .findAllElements('coordinates')
                    .firstOrNull
                    ?.innerText
                    .trim();

                if (nome != null &&
                    nome.isNotEmpty &&
                    coordenadasTexto != null &&
                    coordenadasTexto.isNotEmpty) {
                  final coordenadas = <Map<String, double>>[];

                  final pontos = coordenadasTexto
                      .split(RegExp(r'\s+'))
                      .where((ponto) => ponto.isNotEmpty);

                  for (final ponto in pontos) {
                    final partes = ponto.split(',');

                    if (partes.length >= 2) {
                      final longitude = double.tryParse(partes[0]);
                      final latitude = double.tryParse(partes[1]);

                      if (longitude != null && latitude != null) {
                        coordenadas.add({
                          'longitude': longitude,
                          'latitude': latitude,
                        });
                      }
                    }
                  }

                  quadras.add(nome);

                  poligonos.add({'quadra': nome, 'coordenadas': coordenadas});
                }
              }

              debugPrint('ANTES DO SETSTATE - QUADRAS: ${quadras.length}');
              debugPrint('ANTES DO SETSTATE - POLIGONOS: ${poligonos.length}');

              setState(() {
                _quadrasKml = quadras;
                _poligonosKml = poligonos;
              });

              debugPrint('QUADRAS ARMAZENADAS: ${_quadrasKml.length}');

              debugPrint('POLIGONOS ARMAZENADOS: ${_poligonosKml.length}');

              if (_poligonosKml.isNotEmpty) {
                debugPrint('PRIMEIRA QUADRA: ${_poligonosKml.first['quadra']}');

                debugPrint(
                  'PONTOS DA PRIMEIRA QUADRA: '
                  '${(_poligonosKml.first['coordenadas'] as List).length}',
                );
              }

              // ======================================================
              // QUADRAS
              // ======================================================
            } else if (titulo == 'Quadras') {
              debugPrint('ENTROU NA IMPORTAÇÃO DE QUADRAS');

              final arquivos = await FilePicker.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['txt'],
              );

              if (arquivos.isEmpty) {
                debugPrint('NENHUM ARQUIVO DE QUADRAS SELECIONADO');
                return;
              }

              final arquivo = arquivos.first;

              debugPrint('ARQUIVO DE QUADRAS: ${arquivo.name}');

              final bytes = await arquivo.readAsBytes();
              final conteudo = utf8.decode(bytes);

              final linhas = conteudo
                  .split(RegExp(r'\r?\n'))
                  .where((linha) => linha.trim().isNotEmpty)
                  .toList();

              final relacao = <Map<String, String>>[];

              for (final linha in linhas.skip(1)) {
                final partes = linha.split(RegExp(r'\s+'));

                if (partes.length >= 3) {
                  relacao.add({
                    'area': partes[0],
                    'sc': partes[1],
                    'quadra': partes[2],
                  });
                }
              }

              await DatabaseHelper.instance.substituirQuadras(relacao);
              setState(() {
                _relacaoQuadras = relacao;
              });

              debugPrint(
                'RELAÇÃO AREA/SC/QUADRA: ${_relacaoQuadras.length} registros',
              );

              final quadraKml = _quadrasKml.firstWhere(
                (quadra) => quadra == '249',
                orElse: () => '',
              );

              if (quadraKml.isNotEmpty) {
                debugPrint('TESTE KML → QUADRA: $quadraKml');

                final resultado = _buscarQuadra(quadraKml);

                if (resultado != null) {
                  debugPrint('AREA: ${resultado['area']}');
                  debugPrint('S.C.: ${resultado['sc']}');
                  debugPrint('QUADRA: ${resultado['quadra']}');
                } else {
                  debugPrint('QUADRA $quadraKml NÃO ENCONTRADA NO TXT');
                }
              } else {
                debugPrint('QUADRA 249 NÃO ENCONTRADA NO KML');
              }

              debugPrint('TOTAL DE LINHAS: ${linhas.length}');

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Quadras importadas: ${linhas.length} linhas',
                    ),
                  ),
                );
              }
            }
          },
          icon: Icon(icone, size: 18),
          label: Text(titulo, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class MapaKmlPainter extends CustomPainter {
  final List<Map<String, dynamic>> poligonos;

  MapaKmlPainter(this.poligonos);

  // começa aqui

  String? quadraNoPonto(Offset ponto, Size size) {
    if (poligonos.isEmpty) {
      return null;
    }

    final todosPontos = <Offset>[];

    for (final poligono in poligonos) {
      final coordenadas = poligono['coordenadas'] as List<Map<String, double>>;

      for (final coordenada in coordenadas) {
        todosPontos.add(
          Offset(coordenada['longitude']!, coordenada['latitude']!),
        );
      }
    }

    if (todosPontos.isEmpty) {
      return null;
    }

    double minX = todosPontos.first.dx;
    double maxX = todosPontos.first.dx;
    double minY = todosPontos.first.dy;
    double maxY = todosPontos.first.dy;

    for (final pontoMapa in todosPontos) {
      if (pontoMapa.dx < minX) minX = pontoMapa.dx;
      if (pontoMapa.dx > maxX) maxX = pontoMapa.dx;
      if (pontoMapa.dy < minY) minY = pontoMapa.dy;
      if (pontoMapa.dy > maxY) maxY = pontoMapa.dy;
    }

    final largura = maxX - minX;
    final altura = maxY - minY;

    if (largura == 0 || altura == 0) {
      return null;
    }

    const margem = 20.0;

    final escalaX = (size.width - margem * 2) / largura;
    final escalaY = (size.height - margem * 2) / altura;
    final escala = escalaX < escalaY ? escalaX : escalaY;

    final larguraDesenho = largura * escala;
    final alturaDesenho = altura * escala;

    final deslocamentoX = margem;

    final deslocamentoY = margem;

    for (final poligono in poligonos) {
      final coordenadas = poligono['coordenadas'] as List<Map<String, double>>;

      if (coordenadas.length < 3) {
        continue;
      }

      final caminho = Path();

      for (int i = 0; i < coordenadas.length; i++) {
        final longitude = coordenadas[i]['longitude']!;
        final latitude = coordenadas[i]['latitude']!;

        final x = deslocamentoX + (longitude - minX) * escala;

        final y = deslocamentoY + (maxY - latitude) * escala;

        if (i == 0) {
          caminho.moveTo(x, y);
        } else {
          caminho.lineTo(x, y);
        }
      }

      caminho.close();

      if (caminho.contains(ponto)) {
        return poligono['quadra'] as String;
      }
    }

    return null;
  }

  // termina aqui

  @override
  void paint(Canvas canvas, Size size) {
    if (poligonos.isEmpty) {
      return;
    }

    final pontos = <Offset>[];

    for (final poligono in poligonos) {
      final coordenadas = poligono['coordenadas'] as List<Map<String, double>>;

      for (final coordenada in coordenadas) {
        pontos.add(Offset(coordenada['longitude']!, coordenada['latitude']!));
      }
    }

    if (pontos.isEmpty) {
      return;
    }

    double minX = pontos.first.dx;
    double maxX = pontos.first.dx;
    double minY = pontos.first.dy;
    double maxY = pontos.first.dy;

    for (final ponto in pontos) {
      if (ponto.dx < minX) minX = ponto.dx;
      if (ponto.dx > maxX) maxX = ponto.dx;
      if (ponto.dy < minY) minY = ponto.dy;
      if (ponto.dy > maxY) maxY = ponto.dy;
    }

    final largura = maxX - minX;
    final altura = maxY - minY;

    if (largura == 0 || altura == 0) {
      return;
    }

    const margem = 20.0;

    final escalaX = (size.width - margem * 2) / largura;
    final escalaY = (size.height - margem * 2) / altura;
    final escala = escalaX < escalaY ? escalaX : escalaY;

    final tinta = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final poligono in poligonos) {
      final coordenadas = poligono['coordenadas'] as List<Map<String, double>>;

      if (coordenadas.length < 3) {
        continue;
      }

      final caminho = Path();

      for (int i = 0; i < coordenadas.length; i++) {
        final longitude = coordenadas[i]['longitude']!;
        final latitude = coordenadas[i]['latitude']!;

        final x = margem + (longitude - minX) * escala;
        final y = margem + (maxY - latitude) * escala;

        if (i == 0) {
          caminho.moveTo(x, y);
        } else {
          caminho.lineTo(x, y);
        }
      }

      caminho.close();

      canvas.drawPath(caminho, tinta);

      final pontosQuadra = <Offset>[];

      for (final coordenada in coordenadas) {
        final longitude = coordenada['longitude']!;
        final latitude = coordenada['latitude']!;

        final x = margem + (longitude - minX) * escala;

        final y = margem + (maxY - latitude) * escala;

        pontosQuadra.add(Offset(x, y));
      }

      if (pontosQuadra.isNotEmpty) {
        double somaX = 0;
        double somaY = 0;

        for (final ponto in pontosQuadra) {
          somaX += ponto.dx;
          somaY += ponto.dy;
        }

        final centro = Offset(
          somaX / pontosQuadra.length,
          somaY / pontosQuadra.length,
        );

        final texto = TextPainter(
          text: TextSpan(
            text: poligono['quadra'].toString(),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        texto.layout();

        texto.paint(
          canvas,
          Offset(centro.dx - texto.width / 2, centro.dy - texto.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant MapaKmlPainter oldDelegate) {
    return oldDelegate.poligonos != poligonos;
  }
}

// Tela Visita Imoveis
class TelaVisitaImoveis extends StatefulWidget {
  final String area;
  final String sc;
  final String quadra;
  final List<String> logradouros;

  const TelaVisitaImoveis({
    super.key,
    required this.area,
    required this.sc,
    required this.quadra,
    required this.logradouros,
  });

  @override
  State<TelaVisitaImoveis> createState() => _TelaVisitaImoveisState();
}

class _TelaVisitaImoveisState extends State<TelaVisitaImoveis> {
  DateTime _dataSelecionada = DateTime.now();
  String? _logradouroSelecionado;
  List<Map<String, dynamic>> _enderecosAdicionados = [];
  final TextEditingController _numeroController = TextEditingController();
  final FocusNode _numeroFocusNode = FocusNode();
  final TextEditingController _tipoController = TextEditingController();
  final FocusNode _tipoFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _carregarImoveis();
    debugPrint('TELA 2 - QUANTIDADE DE LOGRADOUROS: ${widget.logradouros.length}');
  }

  String get _dataIso => '${_dataSelecionada.year.toString().padLeft(4, '0')}-'
      '${_dataSelecionada.month.toString().padLeft(2, '0')}-'
      '${_dataSelecionada.day.toString().padLeft(2, '0')}';

  Future<void> _carregarImoveis() async {
    final db = DatabaseHelper.instance;
    final registros = await db.carregarImoveis(
      area: widget.area, sc: widget.sc, quadra: widget.quadra,
    );
    final ruasSalvas = await db.carregarRuasDaQuadra(
      area: widget.area, sc: widget.sc, quadra: widget.quadra,
    );
    if (!mounted) return;
    final porRua = <String, List<Map<String, String>>>{};
    for (final rua in ruasSalvas) { porRua[rua] = <Map<String, String>>[]; }
    for (final r in registros) {
      porRua.putIfAbsent(r['rua'] ?? '', () => []).add({
        'numero': r['numero'] ?? '', 'tipo': r['tipo'] ?? 'CS',
        'status': r['status'] ?? '',
      });
    }
    setState(() {
      _enderecosAdicionados = porRua.entries.map((e) => <String, dynamic>{
        'logradouro': e.key, 'imoveis': e.value,
      }).toList();
    });
  }

  Future<void> _salvarImovel(String rua, Map<String, String> imovel) async {
    final numero = (imovel['numero'] ?? '').trim();
    if (numero.isEmpty) return;
    await DatabaseHelper.instance.salvarImovel(
      area: widget.area, sc: widget.sc, quadra: widget.quadra, rua: rua,
      numero: numero, tipo: imovel['tipo'] ?? 'CS', status: imovel['status'] ?? '',
      dataVisita: _dataIso,
    );
  }

  Future<void> _salvarTipoImovel(String rua, Map<String, String> imovel) async {
    final numero = (imovel['numero'] ?? '').trim();
    if (numero.isEmpty) return;
    await DatabaseHelper.instance.atualizarTipoImovel(
      area: widget.area, sc: widget.sc, quadra: widget.quadra, rua: rua,
      numero: numero, tipo: imovel['tipo'] ?? 'CS',
    );
  }


  Future<void> _pintarMapa() async {
    try {
      var quantidade = 0;
      for (final endereco in _enderecosAdicionados) {
        final rua = endereco['logradouro'] as String;
        final imoveis = (endereco['imoveis'] as List).cast<Map<String, String>>();
        for (final imovel in imoveis) {
          final numero = (imovel['numero'] ?? '').trim();
          if (numero.isEmpty) continue;
          await DatabaseHelper.instance.salvarImovel(
            area: widget.area, sc: widget.sc, quadra: widget.quadra, rua: rua,
            numero: numero, tipo: imovel['tipo'] ?? 'CS',
            status: imovel['status'] ?? '', dataVisita: _dataIso,
          );
          quantidade++;
        }
      }
      if (quantidade == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cadastre pelo menos um imóvel antes de pintar a quadra.'),
        ));
        return;
      }
      final resultado = await DatabaseHelper.instance.finalizarVistoriaQuadra(
        area: widget.area, sc: widget.sc, quadra: widget.quadra, dataVisita: _dataIso,
      );
      if (!mounted) return;
      final mensagem = resultado['larvas'] == true
          ? 'Dados salvos. Quadra marcada com larvas no mapa de visitas.'
          : resultado['concluida'] == true
              ? 'Dados salvos. Todos os imóveis estão trabalhados; quadra concluída.'
              : 'Dados salvos. Pendências registradas; quadra marcada no mapa de pendências.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Não foi possível salvar a vistoria: $e'),
      ));
    }
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CONTROLE DE ZOONOSES',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BOLETIM DE ATIVIDADES DE VIGILÂNCIA E CONTROLE',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      readOnly: true,
                      controller: TextEditingController(
                        text:
                            '${_dataSelecionada.day.toString().padLeft(2, '0')}/'
                            '${_dataSelecionada.month.toString().padLeft(2, '0')}/'
                            '${_dataSelecionada.year}',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'DATA',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_month),
                      ),
                      onTap: () async {
                        final dataEscolhida = await showDatePicker(
                          context: context,
                          initialDate: _dataSelecionada,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );

                        if (dataEscolhida != null) {
                          setState(() {
                            _dataSelecionada = dataEscolhida;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _campoInformacao('ÁREA', widget.area)),
                  const SizedBox(width: 8),
                  Expanded(child: _campoInformacao('S.C.', widget.sc)),
                  const SizedBox(width: 8),
                  Expanded(child: _campoInformacao('QUADRA', widget.quadra)),
                ],
              ),

              const SizedBox(height: 15),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _logradouroSelecionado,
                      decoration: const InputDecoration(
                        labelText: 'ENDEREÇO',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.logradouros.map((logradouro) {
                        return DropdownMenuItem<String>(
                          value: logradouro,
                          child: Text(logradouro),
                        );
                      }).toList(),
                      onChanged: (valor) {
                        setState(() {
                          _logradouroSelecionado = valor;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_logradouroSelecionado == null) {
                          return;
                        }

                        if (!_enderecosAdicionados.any(
                          (endereco) =>
                              endereco['logradouro'] == _logradouroSelecionado,
                        )) {
                          setState(() {
                            _enderecosAdicionados.add({
                              'logradouro': _logradouroSelecionado,
                              'imoveis': <Map<String, String>>[],
                            });
                          });
                          await DatabaseHelper.instance.salvarRuaNaQuadra(
                            area: widget.area, sc: widget.sc, quadra: widget.quadra,
                            rua: _logradouroSelecionado!,
                          );

                          debugPrint(
                            'ENDEREÇO ADICIONADO: $_logradouroSelecionado',
                          );
                        }
                      },
                      child: const Text(
                        'ADICIONAR',
                        style: TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Expanded(
                child: ListView.builder(
                  itemCount: _enderecosAdicionados.length,
                  itemBuilder: (context, index) {
                    final endereco = _enderecosAdicionados[index];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        border: Border.all(),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        children: [
                          // NOME DA RUA
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Text(
                              _enderecosAdicionados[index]['logradouro'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(height: 4),

                          // CABEÇALHO DOS IMÓVEIS
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Center(
                                  child: Text(
                                    'NUM.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Text(
                                    'TIPO',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(child: Center(child: Text('T'))),
                              Expanded(child: Center(child: Text('F'))),
                              Expanded(child: Center(child: Text('D'))),
                              Expanded(child: Center(child: Text('TE'))),
                              Expanded(child: Center(child: Text('P'))),
                              Expanded(child: Center(child: Text('R'))),
                              SizedBox(
                                width: 55,
                                child: Center(
                                  child: Text(
                                    '→',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // IMÓVEIS JÁ CADASTRADOS
                          ...((_enderecosAdicionados[index]['imoveis']
                                  as List<Map<String, String>>)
                              .map((imovel) {
                                return Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Center(
                                        child: Text(
                                          imovel['numero'] ?? '',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                    ),

                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        initialValue: imovel['tipo'] ?? 'CS',
                                        textAlign: TextAlign.center,
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        onChanged: (valor) {
                                          imovel['tipo'] = valor;
                                          _salvarTipoImovel(endereco['logradouro'] as String, imovel);
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setState(() {
                                            imovel['status'] = 'T';
                                          });
                                          _salvarImovel(endereco['logradouro'] as String, imovel);
                                        },
                                        child: Center(
                                          child: Text(
                                            imovel['status'] == 'T' ? 'T' : '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setState(() {
                                            imovel['status'] = 'F';
                                          });
                                          _salvarImovel(endereco['logradouro'] as String, imovel);
                                        },
                                        child: Center(
                                          child: Text(
                                            imovel['status'] == 'F' ? 'F' : '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setState(() {
                                            imovel['status'] = 'D';
                                          });
                                          _salvarImovel(endereco['logradouro'] as String, imovel);
                                        },
                                        child: Center(
                                          child: Text(
                                            imovel['status'] == 'D' ? 'D' : '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setState(() {
                                            imovel['status'] = 'TE';
                                          });
                                          _salvarImovel(endereco['logradouro'] as String, imovel);
                                        },
                                        child: Center(
                                          child: Text(
                                            imovel['status'] == 'TE'
                                                ? 'TE'
                                                : '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setState(() {
                                            imovel['status'] = 'P';
                                          });
                                          _salvarImovel(endereco['logradouro'] as String, imovel);
                                        },
                                        child: Center(
                                          child: Text(
                                            imovel['status'] == 'P' ? 'P' : '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setState(() {
                                            imovel['status'] = 'R';
                                          });
                                          _salvarImovel(endereco['logradouro'] as String, imovel);
                                        },
                                        child: Center(
                                          child: Text(
                                            imovel['status'] == 'R' ? 'R' : '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    SizedBox(
                                      width: 55,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  TelaRecipientesDemandas(
                                                    area: widget.area,
                                                    sc: widget.sc,
                                                    quadra: widget.quadra,
                                                    rua:
                                                        endereco['logradouro']!,
                                                    numero: imovel['numero']!,
                                                    status: imovel['status'] ?? '',
                                                    demandasDisponiveis: _demandasDisponiveis,
                                                    dataVisita: _dataIso,
                                                  ),
                                            ),
                                          );
                                        },
                                        child: const Center(
                                          child: Text(
                                            '→',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              })
                              .toList()),

                          // CAMPO PARA NOVO IMÓVEL
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _numeroController,
                                  focusNode: _numeroFocusNode,
                                  decoration: const InputDecoration(
                                    hintText: 'Número',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.text,
                                  onFieldSubmitted: (valor) {
                                    if (valor.trim().isEmpty) {
                                      return;
                                    }

                                    setState(() {
                                      final imoveis =
                                          endereco['imoveis']
                                              as List<Map<String, String>>;

                                      imoveis.add({
                                        'numero': valor.trim(),
                                        'tipo': 'CS',
                                        'status': '',
                                        'novo': 'true',
                                      });
                                    });
                                    final listaImoveis = (endereco['imoveis'] as List).cast<Map<String, String>>();
                                    _salvarImovel(endereco['logradouro'] as String, listaImoveis.last);
                                    _numeroController.clear();
                                    _tipoController.text = 'CS';
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _tipoFocusNode.requestFocus();
                                        });
                                  },
                                ), // TextFormField
                              ), // Expanded

                              Expanded(
                                flex: 2,
                                child: const Center(child: Text('CS')),
                              ),

                              Expanded(child: const Center(child: Text(''))),
                              Expanded(child: const Center(child: Text(''))),
                              Expanded(child: const Center(child: Text(''))),
                              Expanded(child: const Center(child: Text(''))),
                              Expanded(child: const Center(child: Text(''))),
                              Expanded(child: const Center(child: Text(''))),

                              SizedBox(
                                width: 55,
                                child: const Center(
                                  child: Text(
                                    '→',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _pintarMapa,
                  icon: const Icon(Icons.map),
                  label: const Text('PINTAR O MAPA'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _campoInformacao(String titulo, String valor) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(
            '$titulo: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(valor, style: const TextStyle(fontSize: 17)),
        ],
      ),
    );
  }
}

// Fim da Tela Visita Imoveis

// ============================================================
// TELA 3 - RECIPIENTES E DEMANDAS
// ============================================================

class TelaRecipientesDemandas extends StatefulWidget {
  final String area;
  final String sc;
  final String quadra;
  final String rua;
  final String numero;
  final String status;
  final List<String> demandasDisponiveis;
  final String dataVisita;

  const TelaRecipientesDemandas({
    super.key,
    required this.area,
    required this.sc,
    required this.quadra,
    required this.rua,
    required this.numero,
    required this.status,
    required this.demandasDisponiveis,
    required this.dataVisita,
  });

  @override
  State<TelaRecipientesDemandas> createState() =>
      _TelaRecipientesDemandasState();
}

class _TelaRecipientesDemandasState extends State<TelaRecipientesDemandas> {
  List<Map<String, String>> _recipientes = [];
  String? _demandaSelecionada;
  final TextEditingController _orientacaoController = TextEditingController();
  final List<String> _medidasControle = [
    'Mecânico',
    'Prod. Alternativo',
    'Focal',
    'Nebulização',
    'Vistoriado',
  ];

  final List<Map<String, String>> _grupos = [
    {'codigo': 'A', 'descricao': 'Depósito Elevado'},
    {'codigo': 'B', 'descricao': 'Depósito Não Elevado'},
    {'codigo': 'C', 'descricao': 'Móveis'},
    {'codigo': 'D', 'descricao': 'Fixos'},
    {'codigo': 'E', 'descricao': 'Pneus'},
    {'codigo': 'F', 'descricao': 'Passível Modificação/Alteração'},
    {'codigo': 'G', 'descricao': 'Naturais'},
    {'codigo': 'S', 'descricao': 'Sem recipientes'},
  ];

  final Map<String, List<Map<String, String>>> _tiposPorGrupo = {
    'A': [
      {'codigo': '1', 'descricao': 'Ligado a rede'},
      {'codigo': '2', 'descricao': 'Não Ligado a Rede'},
    ],
    'B': [
      {'codigo': '3', 'descricao': 'Ligado a Rede'},
      {'codigo': '4', 'descricao': 'Não Ligado a Rede'},
    ],
    'C': [
      {'codigo': '5', 'descricao': 'Vaso de planta na Água'},
      {'codigo': '6', 'descricao': 'Vaso de plantas (Diversos)'},
      {'codigo': '7', 'descricao': 'Prato/Pingadeira'},
      {'codigo': '8', 'descricao': 'Consumo animal'},
      {'codigo': '9', 'descricao': 'Deposito para Construção'},
      {'codigo': '10', 'descricao': 'Deposito para Horticultura'},
      {'codigo': '11', 'descricao': 'Piscina desmontavel'},
      {'codigo': '12', 'descricao': 'Lata, frasco, plasticos utilizaveis'},
      {'codigo': '13', 'descricao': 'Garrafas retornaveis'},
      {'codigo': '14', 'descricao': 'Balde / regador'},
      {'codigo': '15', 'descricao': 'Bandeja Geladeira / Ar Cond.'},
      {'codigo': '16', 'descricao': 'Materia Construção'},
      {'codigo': '17', 'descricao': 'Outros'},
    ],
    'D': [
      {'codigo': '18', 'descricao': 'Ralo Interno'},
      {'codigo': '19', 'descricao': 'Ralo Externo'},
      {'codigo': '20', 'descricao': 'Laje'},
      {'codigo': '21', 'descricao': 'Calha'},
      {'codigo': '22', 'descricao': 'Vaso Sanitario/Cx Descarga'},
      {'codigo': '23', 'descricao': 'Piscina'},
      {'codigo': '24', 'descricao': 'Deposito para Construção'},
      {'codigo': '25', 'descricao': 'Deposito para Horticultura'},
      {'codigo': '26', 'descricao': 'Consumo Animal'},
      {'codigo': '27', 'descricao': 'Outros'},
    ],
    'E': [
      {'codigo': '28', 'descricao': 'Pneus'},
      {'codigo': '29', 'descricao': 'Outros Correlatos'},
    ],
    'F': [
      {'codigo': '30', 'descricao': 'Lata Frasco Plastico'},
      {'codigo': '31', 'descricao': 'Garrafa Descartavel'},
      {'codigo': '32', 'descricao': 'Lona Encerado Plastico'},
      {'codigo': '33', 'descricao': 'Entulho de Construção'},
      {'codigo': '34', 'descricao': 'Peças Sucatas'},
      {'codigo': '35', 'descricao': 'Masseira'},
      {'codigo': '36', 'descricao': 'Barco'},
      {'codigo': '37', 'descricao': 'outros'},
    ],
    'G': [
      {'codigo': '38', 'descricao': 'Oco de Arvore, Bambu'},
      {'codigo': '39', 'descricao': 'Bromelias'},
      {'codigo': '40', 'descricao': 'Outros'},
    ],
    'S': [
      {'codigo': '99', 'descricao': 'Sem recipientes'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _carregarRecipientes();
  }

  Future<void> _carregarRecipientes() async {
    final registros = await DatabaseHelper.instance.carregarRecipientes(
      area: widget.area, sc: widget.sc, quadra: widget.quadra,
      rua: widget.rua, numero: widget.numero, dataVisita: widget.dataVisita,
    );
    final demanda = await DatabaseHelper.instance.carregarUltimaDemanda(
      area: widget.area, sc: widget.sc, quadra: widget.quadra,
      rua: widget.rua, numero: widget.numero,
    );
    if (!mounted) return;
    setState(() {
      _recipientes = registros;
      final texto = demanda?['demanda'];
      _demandaSelecionada = texto != null && widget.demandasDisponiveis.contains(texto) ? texto : null;
      _orientacaoController.text = demanda?['orientacao'] ?? '';
    });
  }

  Future<void> _salvarDemanda() async {
    if (widget.status != 'T') return;
    if ((_demandaSelecionada ?? '').isEmpty && _orientacaoController.text.trim().isEmpty) return;
    await DatabaseHelper.instance.salvarDemanda(
      area: widget.area, sc: widget.sc, quadra: widget.quadra,
      rua: widget.rua, numero: widget.numero,
      demanda: _demandaSelecionada ?? '', orientacao: _orientacaoController.text.trim(),
    );
  }

  Future<void> _salvarRecipientes() async {
    await DatabaseHelper.instance.salvarRecipientes(
      area: widget.area, sc: widget.sc, quadra: widget.quadra,
      rua: widget.rua, numero: widget.numero, dataVisita: widget.dataVisita,
      recipientes: _recipientes,
    );
  }

  Widget _celulaCabecalho(String texto) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  Widget _celulaVazia() {
    return const SizedBox(height: 55);
  }

  Widget _campoInformacao(String titulo, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(
            '$titulo: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  TableRow _novaLinhaMedida() {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: DropdownButtonFormField<String>(
            initialValue: null,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            hint: const Text('Escolher medida'),
            items: _medidasControle.map((medida) {
              return DropdownMenuItem<String>(
                value: medida,
                child: Text(medida),
              );
            }).toList(),
            onChanged: widget.status != 'T' ? null : (valor) {
              if (valor == null) return;

              setState(() {
                _recipientes.add({
                  'medida': valor,
                  'grupo': '',
                  'tipo': '',
                  'existente': '',
                  'agua': '',
                  'larva': '',
                });
              });
              _salvarRecipientes();
            },
          ),
        ),
        _celulaVazia(),
        _celulaVazia(),
        _celulaVazia(),
        _celulaVazia(),
        _celulaVazia(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROLE DE ZOONOSES')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TELA 3 - RECIPIENTES E DEMANDAS',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: _campoInformacao('ÁREA', widget.area)),
                const SizedBox(width: 10),
                Expanded(child: _campoInformacao('S.C.', widget.sc)),
                const SizedBox(width: 10),
                Expanded(child: _campoInformacao('QUADRA', widget.quadra)),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _campoInformacao('RUA', widget.rua)),
                const SizedBox(width: 10),
                Expanded(child: _campoInformacao('IMÓVEL', widget.numero)),
              ],
            ),

            if (widget.status != 'T')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Consulta somente: para cadastrar ou editar, marque o imóvel como T (Trabalhado).',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.deepOrange)),
              ),
            const SizedBox(height: 20),

            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    // CABEÇALHO FIXO
                    Table(
                      border: TableBorder.all(),
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      columnWidths: const {
                        0: FlexColumnWidth(1.6),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.2),
                        3: FlexColumnWidth(1.0),
                        4: FlexColumnWidth(1.0),
                        5: FlexColumnWidth(1.0),
                      },
                      children: [
                        TableRow(
                          children: [
                            _celulaCabecalho('Medidas de\nControle'),
                            _celulaCabecalho('Grupo'),
                            _celulaCabecalho('Tipo'),
                            _celulaCabecalho('Existente'),
                            _celulaCabecalho('C/Água'),
                            _celulaCabecalho('C/Larva'),
                          ],
                        ),
                      ],
                    ),

                    // SOMENTE AS LINHAS ROLAM
                    Expanded(
                      child: SingleChildScrollView(
                        child: Table(
                          border: TableBorder.all(),
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          columnWidths: const {
                            0: FlexColumnWidth(1.6),
                            1: FlexColumnWidth(1.2),
                            2: FlexColumnWidth(1.2),
                            3: FlexColumnWidth(1.0),
                            4: FlexColumnWidth(1.0),
                            5: FlexColumnWidth(1.0),
                          },
                          children: [
                            ..._recipientes.map((recipiente) {
                              return TableRow(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: DropdownButtonFormField<String>(
                                      initialValue:
                                          recipiente['medida']!.isEmpty
                                          ? null
                                          : recipiente['medida'],
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                      ),
                                      hint: const Text('Escolher medida'),
                                      items: _medidasControle.map((medida) {
                                        return DropdownMenuItem<String>(
                                          value: medida,
                                          child: Text(medida),
                                        );
                                      }).toList(),
                                      onChanged: widget.status != 'T' ? null : (valor) {
                                        setState(() {
                                          recipiente['medida'] = valor ?? '';
                                        });
                                        _salvarRecipientes();
                                      },
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: recipiente['grupo']!.isEmpty
                                          ? null
                                          : recipiente['grupo'],
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                      ),
                                      hint: const Text('Escolher grupo'),
                                      items: _grupos.map((grupo) {
                                        return DropdownMenuItem<String>(
                                          value: grupo['codigo'],
                                          child: Text(
                                            '${grupo['codigo']} - ${grupo['descricao']}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: widget.status != 'T' ? null : (valor) {
                                        setState(() {
                                          recipiente['grupo'] = valor ?? '';
                                          recipiente['tipo'] = '';
                                        });
                                        _salvarRecipientes();
                                      },
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: recipiente['tipo']!.isEmpty
                                          ? null
                                          : recipiente['tipo'],
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                      ),
                                      hint: const Text('Escolher tipo'),
                                      items:
                                          (_tiposPorGrupo[recipiente['grupo']] ??
                                                  [])
                                              .map((tipo) {
                                                return DropdownMenuItem<String>(
                                                  value: tipo['codigo'],
                                                  child: Text(
                                                    '${tipo['codigo']} - ${tipo['descricao']}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                );
                                              })
                                              .toList(),
                                      onChanged: widget.status != 'T' || recipiente['grupo']!.isEmpty
                                          ? null
                                          : (valor) {
                                              setState(() {
                                                recipiente['tipo'] =
                                                    valor ?? '';
                                              });
                                              _salvarRecipientes();
                                            },
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: TextFormField(
                                      enabled: widget.status == 'T',
                                      initialValue: recipiente['existente'],
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                        hintText: '0',
                                      ),
                                      onChanged: (valor) {
                                        recipiente['existente'] = valor;
                                        _salvarRecipientes();
                                      },
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: TextFormField(
                                      enabled: widget.status == 'T',
                                      initialValue: recipiente['agua'],
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                        hintText: '0',
                                      ),
                                      onChanged: (valor) {
                                        recipiente['agua'] = valor;
                                        _salvarRecipientes();
                                      },
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: TextFormField(
                                      enabled: widget.status == 'T',
                                      initialValue: recipiente['larva'],
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                        hintText: '0',
                                      ),
                                      onChanged: (valor) {
                                        recipiente['larva'] = valor;
                                        _salvarRecipientes();
                                      },
                                    ),
                                  ),
                                ],
                              );
                            }),
                            _novaLinhaMedida(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _demandaSelecionada,
                    onChanged: widget.status == 'T' ? (valor) => setState(() { _demandaSelecionada = valor; }) : null,
                    decoration: const InputDecoration(
                      labelText: 'Demanda / Reclamação',
                      border: OutlineInputBorder(),
                    ),
                    items: widget.demandasDisponiveis.map((item) => DropdownMenuItem<String>(
                      value: item, child: Text(item, overflow: TextOverflow.ellipsis),
                    )).toList(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(
                    enabled: widget.status == 'T',
                    controller: _orientacaoController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Orientação / observações',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            SafeArea(
              child: Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () async {
                    await _salvarRecipientes();
                    await _salvarDemanda();
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  child: const Text('OK'),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}
