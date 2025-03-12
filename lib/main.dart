import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';
import 'package:tenacity/auth_wrapper.dart';
import 'package:tenacity/src/controllers/announcement_controller.dart';
import 'package:tenacity/src/controllers/auth_controller.dart';
import 'package:tenacity/src/controllers/chat_controller.dart';
import 'package:tenacity/src/controllers/invoice_controller.dart';
import 'package:tenacity/src/controllers/payment_controller.dart';
import 'package:tenacity/src/controllers/profile_controller.dart';
import 'package:tenacity/src/controllers/timetable_controller.dart';
import 'package:tenacity/src/services/chat_service.dart';
import 'package:tenacity/src/services/timetable_service.dart';
import 'firebase_options.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  Stripe.publishableKey =
      "pk_test_51NGMmNGpgjvnJDO9rbaApJ4qNxiyvX3AXN36DHAvukFzmWdzrDVaYgAahdWIDZgObUsCCWPaI1ZcYdDjOfWOYeme001iWgc7lB";
  Stripe.merchantIdentifier = "merchant.com.tenacitytutoring.tenacity";
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>(
          create: (_) => AuthController(),
        ),
        ChangeNotifierProvider<ProfileController>(
          create: (_) => ProfileController(),
        ),
        ChangeNotifierProvider<AnnouncementsController>(
          create: (_) => AnnouncementsController(),
        ),
        ChangeNotifierProxyProvider<AuthController, ChatController>(
          create: (_) => ChatController(
            chatService: ChatService(),
            userId: '',
          ),
          update: (_, authController, previousChatController) {
            return ChatController(
              chatService: ChatService(),
              userId: authController.currentUser?.uid ?? '',
            );
          },
        ),
        ChangeNotifierProvider<TimetableController>(
          create: (_) => TimetableController(service: TimetableService()),
        ),
        ChangeNotifierProvider<InvoiceController>(
            create: (_) => InvoiceController()),
        ChangeNotifierProvider<PaymentController>(
          create: (_) => PaymentController(),
        )
      ],
      child: const Tenacity(),
    ),
  );
}

class Tenacity extends StatelessWidget {
  const Tenacity({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tenacity Tutoring',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1C71AF)),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}
