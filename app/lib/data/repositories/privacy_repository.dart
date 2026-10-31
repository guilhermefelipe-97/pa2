abstract class PrivacyRepository {
  Future<bool> silentDefault(String uid);
  Future<void> setSilentDefault(String uid, bool value);
}

const silentScope =
    'Modo silencioso oculta esta atividade do feed Amigos, incluindo foto, comentário, fonte e selo. Seu nome e todos os dados continuam na ficha do local, no perfil, nas agregações, no Perto e na decisão. A preferência vale só para futuras avaliações e visitas.';
