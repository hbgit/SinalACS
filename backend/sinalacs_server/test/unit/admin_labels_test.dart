import 'package:sinalacs_server/src/application/admin/admin_labels.dart';
import 'package:test/test.dart';

void main() {
  const id = '5b6f2c1e-0000-4000-8000-00000000a18f';

  test('rótulo do paciente = # + últimos 4 hex em maiúsculas', () {
    expect(AdminLabels.patient(id), '#A18F');
    expect(AdminLabels.patient('abc'), '#????');
  });

  test('rótulo do usuário nunca contém nome; paciente vira Paciente #XXXX', () {
    expect(AdminLabels.user(role: 'patient', id: id), 'Paciente #A18F');
    expect(AdminLabels.user(role: 'admin', id: id, enrollmentId: 'ADM-001'), 'ADM-001 (Administrador)');
    expect(AdminLabels.user(role: 'acs', id: id, enrollmentId: 'ACS-001'), 'ACS-001 (ACS)');
    expect(AdminLabels.user(role: 'coordinator', id: id), 'Coordenador #A18F');
  });

  test('paciente ignora matrícula (não há matrícula de paciente a mostrar)', () {
    expect(AdminLabels.user(role: 'patient', id: id, enrollmentId: 'X'), 'Paciente #A18F');
  });
}
