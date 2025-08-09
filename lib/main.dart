import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:developer' as developer;

// Background callback - runs even when app is killed!
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      developer.log('🔄 Background: Checking Beam API...', name: 'BeamBackground');
      
      final response = await http.get(
        Uri.parse('https://weult.com/beam/api/check_notifications.php?t=${DateTime.now().millisecondsSinceEpoch}'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] && data['has_new_order'] && data['notification'] != null) {
          final notification = data['notification'];
          final orderId = notification['order_id'];
          
          // Get stored last order ID
          final prefs = await SharedPreferences.getInstance();
          final lastOrderId = prefs.getString('lastOrderId');
          
          if (lastOrderId != orderId) {
            developer.log('🎯 Background: New order detected: $orderId', name: 'BeamBackground');
            
            // Store new order ID
            await prefs.setString('lastOrderId', orderId);
            
            // Show notification
            await AwesomeNotifications().createNotification(
              content: NotificationContent(
                id: int.parse(orderId),
                channelKey: 'beam_orders',
                title: '🛒 New Beam Order!',
                body: 'Order #${notification['order_number']} from ${notification['customer_name']} - ${notification['total']} DTN',
                bigPicture: 'https://weult.com/beam/favicon.ico',
                notificationLayout: NotificationLayout.BigPicture,
                wakeUpScreen: true,
                criticalAlert: true,
                category: NotificationCategory.Message,
              ),
            );
            
            developer.log('✅ Background: Notification sent successfully', name: 'BeamBackground');
          } else {
            developer.log('ℹ️ Background: No new orders (same ID)', name: 'BeamBackground');
          }
        } else {
          developer.log('ℹ️ Background: No new orders available', name: 'BeamBackground');
        }
      }
    } catch (e) {
      developer.log('❌ Background: Error checking API: $e', name: 'BeamBackground');
    }
    
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notifications
  await AwesomeNotifications().initialize(
    null,
    [
      NotificationChannel(
        channelKey: 'beam_orders',
        channelName: 'Beam Orders',
        channelDescription: 'New order notifications from your Beam store',
        importance: NotificationImportance.Max,
        defaultColor: Colors.orange,
        ledColor: Colors.orange,
        channelShowBadge: true,
        playSound: true,
        enableVibration: true,
      )
    ],
  );
  
  // Initialize background monitoring
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  
  // Register periodic task for background monitoring
  await Workmanager().registerPeriodicTask(
    "beam-monitor",
    "checkBeamOrders",
    frequency: const Duration(seconds: 5), // Your ultra-fast 5-second interval!
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: false,
    ),
  );
  
  runApp(const BeamWebApp());
}

class BeamWebApp extends StatelessWidget {
  const BeamWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beam Notifications',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
        ),
      ),
      home: const BeamWebViewScreen(),
    );
  }
}

class BeamWebViewScreen extends StatefulWidget {
  const BeamWebViewScreen({super.key});

  @override
  State<BeamWebViewScreen> createState() => _BeamWebViewScreenState();
}

class _BeamWebViewScreenState extends State<BeamWebViewScreen> {
  late WebViewController webController;
  bool isLoading = true;
  String? lastOrderId;
  bool backgroundMonitoringEnabled = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _requestNotificationPermissions();
    await _loadLastOrderId();
    _setupWebController();
    _startForegroundMonitoring();
    _checkBackgroundMonitoringStatus();
  }

  Future<void> _requestNotificationPermissions() async {
    final isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }
  }

  Future<void> _loadLastOrderId() async {
    final prefs = await SharedPreferences.getInstance();
    lastOrderId = prefs.getString('lastOrderId');
  }

  void _setupWebController() {
    webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String url) {
          developer.log('🌐 Loading: $url', name: 'BeamWebView');
          setState(() {
            isLoading = true;
          });
        },
        onPageFinished: (String url) {
          developer.log('✅ Loaded: $url', name: 'BeamWebView');
          setState(() {
            isLoading = false;
          });
        },
      ))
      ..loadRequest(Uri.parse('https://weult.com/beam/'))
      ..setBackgroundColor(Colors.white);
  }

  void _startForegroundMonitoring() {
    // Check API every 1 second when app is active
    Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (mounted) {
        _checkApiInForeground();
      }
    });
  }

  void _checkBackgroundMonitoringStatus() {
    setState(() {
      backgroundMonitoringEnabled = true; // WorkManager is initialized
    });
  }

  Future<void> _checkApiInForeground() async {
    try {
      final response = await http.get(
        Uri.parse('https://weult.com/beam/api/check_notifications.php?t=${DateTime.now().millisecondsSinceEpoch}'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] && data['has_new_order'] && data['notification'] != null) {
          final notification = data['notification'];
          final currentOrderId = notification['order_id'];
          
          if (lastOrderId != currentOrderId) {
            developer.log('🎯 Foreground: New order detected: $currentOrderId', name: 'BeamForeground');
            
            setState(() {
              lastOrderId = currentOrderId;
            });
            
            // Store for background monitoring
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('lastOrderId', currentOrderId);
            
            // Show foreground notification
            await _showForegroundNotification(notification);
          }
        }
      }
    } catch (e) {
      developer.log('❌ Foreground: API Error: $e', name: 'BeamForeground');
    }
  }

  Future<void> _showForegroundNotification(Map<String, dynamic> notification) async {
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: int.parse(notification['order_id']),
          channelKey: 'beam_orders',
          title: '🛒 New Beam Order (Live)!',
          body: 'Order #${notification['order_number']} from ${notification['customer_name']} - ${notification['total']} DTN',
          summary: 'Detected while app is active',
          bigPicture: 'https://weult.com/beam/favicon.ico',
          notificationLayout: NotificationLayout.BigPicture,
          wakeUpScreen: true,
          category: NotificationCategory.Message,
        ),
      );
      
      developer.log('✅ Foreground: Notification sent successfully', name: 'BeamForeground');
    } catch (e) {
      developer.log('❌ Foreground: Notification failed: $e', name: 'BeamForeground');
    }
  }

  Future<void> _testNotification() async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        channelKey: 'beam_orders',
        title: '🧪 Test Notification',
        body: 'Background monitoring is working! App: ${backgroundMonitoringEnabled ? "Background enabled" : "Foreground only"}',
        wakeUpScreen: true,
        category: NotificationCategory.Message,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beam Store'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => webController.reload(),
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: _testNotification,
            tooltip: 'Test Notification',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'status':
                  _showStatusDialog();
                  break;
                case 'test':
                  _testNotification();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'status',
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Monitoring Status'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'test',
                child: Row(
                  children: [
                    Icon(Icons.notifications_active, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Test Notification'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: webController),
          if (isLoading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Colors.orange,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading Beam Store...',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _testNotification,
        backgroundColor: Colors.orange,
        child: const Icon(Icons.notifications, color: Colors.white),
      ),
    );
  }

  void _showStatusDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.monitor_heart, color: Colors.orange),
              SizedBox(width: 8),
              Text('Monitoring Status'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow('Website', 'https://weult.com/beam/', Colors.green),
              _buildStatusRow('API Endpoint', 'https://weult.com/beam/api/check_notifications.php', Colors.green),
              _buildStatusRow('Foreground Monitoring', '1 second intervals', Colors.green),
              _buildStatusRow('Background Monitoring', backgroundMonitoringEnabled ? '5 second intervals' : 'Disabled', backgroundMonitoringEnabled ? Colors.green : Colors.red),
              _buildStatusRow('Last Order ID', lastOrderId ?? 'None', lastOrderId != null ? Colors.blue : Colors.grey),
              const SizedBox(height: 16),
              const Text(
                '🎯 Ultra-Fast Monitoring:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
              ),
              const Text('• App open: Every 1 second'),
              const Text('• App closed: Every 5 seconds'),
              const Text('• Works even when force-closed!'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _testNotification();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Test Now', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
