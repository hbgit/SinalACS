import 'package:flutter/material.dart';

class SinalAcsApp extends StatelessWidget {
  const SinalAcsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SinalACS Paciente',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF22C55E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PatientLoginScreen(),
    );
  }
}

class PatientLoginScreen extends StatelessWidget {
  const PatientLoginScreen({super.key});

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
                    Icons.favorite_rounded,
                    size: 72,
                    color: Color(0xFF22C55E),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'SinalACS',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Acesso do paciente',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'CPF',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Data de nascimento',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    label: 'Entrar na triagem do paciente',
                    button: true,
                    child: FilledButton(
                      key: const Key('enter_button'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const TriageScreen()),
                        );
                      },
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

class TriageScreen extends StatefulWidget {
  const TriageScreen({super.key});

  @override
  State<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends State<TriageScreen> {
  bool chestPain = false;
  bool difficultyBreathing = false;
  bool fever = false;
  bool persistentVomiting = false;
  bool bleeding = false;
  bool severeWeakness = false;

  String get riskSummary {
    if (chestPain || difficultyBreathing || severeWeakness || bleeding) {
      return 'Risco: Vermelho';
    }
    if (fever || persistentVomiting) {
      return 'Risco: Amarelo';
    }
    return 'Risco: Verde';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Triagem rápida'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selecione os sintomas que você está sentindo agora:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              _OptionToggle(
                keyName: 'chest_pain',
                label: 'Dor no peito',
                value: chestPain,
                onChanged: (value) => setState(() => chestPain = value),
              ),
              _OptionToggle(
                keyName: 'difficulty_breathing',
                label: 'Dificuldade para respirar',
                value: difficultyBreathing,
                onChanged: (value) => setState(() => difficultyBreathing = value),
              ),
              _OptionToggle(
                keyName: 'fever',
                label: 'Febre',
                value: fever,
                onChanged: (value) => setState(() => fever = value),
              ),
              _OptionToggle(
                keyName: 'persistent_vomiting',
                label: 'Vômitos persistentes',
                value: persistentVomiting,
                onChanged: (value) => setState(() => persistentVomiting = value),
              ),
              _OptionToggle(
                keyName: 'bleeding',
                label: 'Sangramento',
                value: bleeding,
                onChanged: (value) => setState(() => bleeding = value),
              ),
              _OptionToggle(
                keyName: 'severe_weakness',
                label: 'Fraqueza intensa',
                value: severeWeakness,
                onChanged: (value) => setState(() => severeWeakness = value),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Resultado da triagem'),
                    const SizedBox(height: 8),
                    Text(
                      riskSummary,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('submit_triage'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StatusScreen(riskLabel: riskSummary),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Enviar triagem'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusScreen extends StatelessWidget {
  const StatusScreen({required this.riskLabel, super.key});

  final String riskLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Status da solicitação')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Solicitação enviada',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('Status: Em análise pela equipe de atenção à saúde.'),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Etapa atual', style: TextStyle(color: Colors.white60)),
                  const SizedBox(height: 8),
                  Text('Aguardando resposta do ACS', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 16),
                  Text(
                    riskLabel,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('Voltar ao início'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionToggle extends StatelessWidget {
  const _OptionToggle({
    required this.keyName,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String keyName;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      key: Key(keyName),
      value: value,
      onChanged: (checked) => onChanged(checked ?? false),
      title: Text(label),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
