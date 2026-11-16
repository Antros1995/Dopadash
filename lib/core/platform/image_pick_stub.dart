import 'image_pick.dart';

/// Fuori dal browser la scelta delle foto non è disponibile.
bool get canPickImages => false;

Future<PickedImage?> pickImage({int maxSide = 1400}) async => null;
