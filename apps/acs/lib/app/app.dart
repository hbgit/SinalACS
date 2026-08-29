import 'package:flutter/material.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

class SinalAcsApp extends StatelessWidget {
  const SinalAcsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SinalACS ACS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101827),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2FC6A0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _matriculaController = TextEditingController(text: 'ACS-001');
  final _senhaController = TextEditingController(text: '123456');

  @override
  void dispose() {
    _matriculaController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _login() {
    if (_matriculaController.text.trim().isEmpty || _senhaController.text.trim().isEmpty) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.local_hospital_rounded,
                    size: 72,
                    color: Color(0xFF2FC6A0),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'SinalACS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    key: const Key('matricula_field'),
                    controller: _matriculaController,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('senha_field'),
                    controller: _senhaController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    label: 'Entrar no painel de priorização',
                    button: true,
                    child: FilledButton(
                      key: const Key('login_button'),
                      onPressed: _login,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Entrar'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final patients = [
      _PriorityPatient(
        name: 'Maria Souza',
        riskLabel: 'Risco: Vermelho',
        tag: 'Urgência',
      ),
      _PriorityPatient(
        name: 'João Oliveira',
        riskLabel: 'Risco: Amarelo',
        tag: 'Observação',
      ),
      _PriorityPatient(
        name: 'Ana Costa',
        riskLabel: 'Risco: Verde',
        tag: 'Rotina',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel de Priorização'),
        actions: [
          IconButton(
            tooltip: 'Territorialização',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TerritorializationScreen()),
              );
            },
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF122033),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Microárea: Norte 02',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text('12 pacientes ativos • 3 alertas pendentes'),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: patients.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final patient = patients[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: patient.tag == 'Urgência'
                          ? Colors.red.shade400
                          : patient.tag == 'Observação'
                              ? Colors.orange.shade400
                              : Colors.green.shade400,
                      child: Text(patient.name.substring(0, 1)),
                    ),
                    title: Text(patient.name),
                    subtitle: Text(patient.riskLabel),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text(patient.tag),
                          backgroundColor: patient.tag == 'Urgência'
                              ? Colors.red.shade900
                              : patient.tag == 'Observação'
                                  ? Colors.orange.shade900
                                  : Colors.green.shade900,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Registrar visita',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => VisitRegistrationScreen(
                                  patientName: patient.name,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.assignment_turned_in_outlined),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class TerritorializationScreen extends StatelessWidget {
  const TerritorializationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final areas = ['Norte 02', 'Sul 04', 'Centro 01'];

    return Scaffold(
      appBar: AppBar(title: const Text('Territorialização')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: areas.length,
        itemBuilder: (context, index) {
          final area = areas[index];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(area),
              subtitle: const Text('12 pacientes • 3 alertas pendentes'),
              trailing: const Icon(Icons.arrow_forward_ios),
            ),
          );
        },
      ),
    );
  }
}

class VisitRegistrationScreen extends StatefulWidget {
  const VisitRegistrationScreen({required this.patientName, super.key});

  final String patientName;

  @override
  State<VisitRegistrationScreen> createState() => _VisitRegistrationScreenState();
}

class _VisitRegistrationScreenState extends State<VisitRegistrationScreen> {
  final _notesController = TextEditingController(
    text: 'Visita inicial registrada em campo.',
  );

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _registerVisit() async {
    final queue = OfflineVisitQueue();
    await queue.add(
      OfflineVisitRecord(
        patientName: widget.patientName,
        risk: 'VERMELHO',
        status: 'PENDENTE',
      ),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Visita salva localmente e enviada para sincronização.'),
      ),
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar visita')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.patientName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Status da visita'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'em_andamento', label: Text('Em andamento')),
                ButtonSegment(value: 'concluida', label: Text('Concluída')),
              ],
              selected: const {'em_andamento'},
              onSelectionChanged: (_) {},
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Observações',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _registerVisit,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar visita'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityPatient {
  const _PriorityPatient({
    required this.name,
    required this.riskLabel,
    required this.tag,
  });

  final String name;
  final String riskLabel;
  final String tag;
}
