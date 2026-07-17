// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'BULB VPN';

  @override
  String get tagline => 'Rápido. Seguro. Privado.';

  @override
  String get home => 'Inicio';

  @override
  String get servers => 'Servidores';

  @override
  String get stats => 'Estadísticas';

  @override
  String get settings => 'Ajustes';

  @override
  String get profile => 'Perfil';

  @override
  String get connected => 'Conectado';

  @override
  String get disconnected => 'Desconectado';

  @override
  String get connecting => 'Conectando...';

  @override
  String get disconnecting => 'Desconectando...';

  @override
  String get protected => 'Protegido';

  @override
  String get unprotected => 'Desprotegido';

  @override
  String get quickConnect => 'Conexión Rápida';

  @override
  String get disconnect => 'Desconectar';

  @override
  String get selectServer => 'Seleccionar Servidor';

  @override
  String get searchServers => 'Buscar servidores...';

  @override
  String get protocol => 'Protocolo';

  @override
  String get autoConnect => 'Conexión Automática';

  @override
  String get autoConnectDescription => 'Conectar al iniciar la app';

  @override
  String get killSwitch => 'Interruptor de Emergencia';

  @override
  String get killSwitchDescription => 'Bloquear si el VPN se cae';

  @override
  String get darkMode => 'Modo Oscuro';

  @override
  String get splitTunneling => 'Túnel Dividido';

  @override
  String get splitTunnelingDescription => 'Elegir apps para el VPN';

  @override
  String get threatProtection => 'Protección contra Amenazas';

  @override
  String get threatProtectionDescription => 'Bloquear anuncios y rastreadores';

  @override
  String get upgradeToPro => 'Actualizar a Pro';

  @override
  String get upgradeToPremium => 'Actualizar a Premium';

  @override
  String get restorePurchases => 'Restaurar Compras';

  @override
  String get continueAsGuest => 'Continuar como Invitado';

  @override
  String get signIn => 'Iniciar Sesión';

  @override
  String get signUp => 'Registrarse';

  @override
  String get email => 'Correo electrónico';

  @override
  String get password => 'Contraseña';

  @override
  String get confirmPassword => 'Confirmar Contraseña';

  @override
  String get forgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get noServersFound => 'No se encontraron servidores';

  @override
  String get checkConnection => 'Verifica tu conexión a internet';

  @override
  String get retry => 'Reintentar';

  @override
  String get favorites => 'Favoritos';

  @override
  String get recommended => 'Recomendado';

  @override
  String get streaming => 'Streaming';

  @override
  String get gaming => 'Juegos';

  @override
  String get download => 'Descarga';

  @override
  String get upload => 'Subida';

  @override
  String get session => 'Sesión';

  @override
  String get dataUsed => 'Datos Usados';

  @override
  String get connectionHistory => 'Historial de Conexiones';

  @override
  String get clearHistory => 'Borrar Historial';

  @override
  String get noHistoryYet => 'Sin conexiones aún';

  @override
  String get vpnPermissionRequired => 'Permiso de VPN Requerido';

  @override
  String get vpnPermissionDescription =>
      'BULB VPN necesita permiso para crear una conexión VPN.';

  @override
  String get grantPermission => 'Otorgar Permiso';

  @override
  String get maybeLater => 'Quizás Después';

  @override
  String get onboarding1Title => 'Protege tu Privacidad';

  @override
  String get onboarding1Subtitle =>
      'BULB VPN encripta tu conexión a internet y oculta tu dirección IP real.';

  @override
  String get onboarding2Title => 'Mantente Seguro en WiFi Público';

  @override
  String get onboarding2Subtitle =>
      'Las redes WiFi públicas son campos de caza para hackers.';

  @override
  String get onboarding3Title => 'Streaming Sin Límites';

  @override
  String get onboarding3Subtitle =>
      'Accede a contenido de todo el mundo con servidores optimizados.';

  @override
  String get onboarding4Title => 'Estás Listo';

  @override
  String get onboarding4Subtitle =>
      'Un toque es todo lo que necesitas. Conéctate a un servidor seguro al instante.';

  @override
  String get getStarted => 'Empezar';

  @override
  String get skip => 'Omitir';

  @override
  String get next => 'Siguiente';
}
