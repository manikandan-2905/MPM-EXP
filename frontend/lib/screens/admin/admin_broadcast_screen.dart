import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/preferences_service.dart';
import '../../config/constants.dart';

class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({Key? key}) : super(key: key);

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final ApiService _apiService = ApiService();

  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _urlController = TextEditingController();

  String _selectedTarget = 'ALL'; // 'ALL', 'CUSTOMERS', 'RIDERS'
  String _selectedType = 'ANNOUNCEMENT'; // 'UPDATE', 'OFFER', 'RIDERS_ONLINE', 'ANNOUNCEMENT'
  bool _isSending = false;
  bool _isLoadingStats = true;

  Map<String, dynamic> _deviceStats = {
    'totalDevices': 0,
    'customersCount': 0,
    'ridersCount': 0,
    'adminCount': 0,
  };

  @override
  void initState() {
    super.initState();
    _fetchStats();
    // Start clean with NO dummy text pre-filled
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoadingStats = true);
    final stats = await _apiService.getNotificationStats();
    if (mounted) {
      setState(() {
        _deviceStats = stats;
        _isLoadingStats = false;
      });
    }
  }

  void _applyTemplate(String type) {
    setState(() {
      _selectedType = type;
      if (type == 'UPDATE') {
        _selectedTarget = 'ALL';
        _titleController.text = '⚡ New ZIPPO Update Available!';
        _messageController.text =
            'A new version of ZIPPO is available with faster 15-min tracking. Tap to download and install now!';
        _urlController.text = AppConstants.appDownloadUrl;
      } else if (type == 'OFFER') {
        _selectedTarget = 'CUSTOMERS';
        _titleController.text = '🔥 Special Bazar Offer Today!';
        _messageController.text =
            'Special discounts on food and grocery delivery in Melapalayam! Order now for guaranteed 15-minute express delivery.';
        _urlController.text = 'https://zippo-mpm.onrender.com';
      } else if (type == 'RIDERS_ONLINE') {
        _selectedTarget = 'CUSTOMERS';
        _titleController.text = '🛵 ZIPPO Riders are Online Now!';
        _messageController.text =
            'Need medicines, groceries, or food? Order now for guaranteed 15-minute express delivery in Melapalayam!';
        _urlController.text = 'https://zippo-mpm.onrender.com';
      } else {
        // Clear all fields for custom broadcast
        _titleController.clear();
        _messageController.clear();
        _urlController.clear();
      }
    });
  }

  Future<void> _sendBroadcast() async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();
    final actionUrl = _urlController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please enter both a Notification Title and Message Body'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final targetCount = _getTargetCount(_selectedTarget);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.campaign_rounded, color: Color(0xFF76C457), size: 26),
            SizedBox(width: 8),
            Text('Confirm Push Alert', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to broadcast to .',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📌 ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(message, style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '⚠️ This delivers a real-time push alert to devices ( registered) even if their app is completely closed.',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.3),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF76C457),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Broadcast Now', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSending = true);

    try {
      final res = await _apiService.sendAdminBroadcast(
        adminPassword: 'admin123',
        target: _selectedTarget,
        title: title,
        message: message,
        type: _selectedType,
        actionUrl: actionUrl.isNotEmpty ? actionUrl : null,
      );

      setState(() => _isSending = false);

      if (res['success'] == true) {
        final stats = res['stats'] ?? {};
        final total = stats['totalRecipients'] ?? 0;
        final sent = stats['successCount'] ?? 0;

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 26),
                SizedBox(width: 8),
                Text('Broadcast Dispatched!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            content: Text(
              'Push notification successfully sent to  targeted devices ( delivered successfully).\n\n'
              'Installed users will receive the alert on their phone notification bar immediately.',
              style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF334155)),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _fetchStats();
                },
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to send broadcast'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSending = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: '),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  String _getTargetLabel(String target) {
    switch (target) {
      case 'CUSTOMERS':
        return 'Customers Only';
      case 'RIDERS':
        return 'Riders Only';
      default:
        return 'All Users (Customers & Riders)';
    }
  }

  int _getTargetCount(String target) {
    switch (target) {
      case 'CUSTOMERS':
        return _deviceStats['customersCount'] ?? 0;
      case 'RIDERS':
        return _deviceStats['ridersCount'] ?? 0;
      default:
        return _deviceStats['totalDevices'] ?? 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();
    final actionUrl = _urlController.text.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.campaign_rounded, color: Color(0xFF76C457), size: 22),
            SizedBox(width: 8),
            Text('Push Broadcast Desk', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh audience count',
            onPressed: _fetchStats,
          ),
        ],
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Live Audience Overview Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.sensors_rounded, color: Color(0xFF76C457), size: 18),
                          SizedBox(width: 6),
                          Text(
                            'LIVE CONNECTED DEVICES',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF76C457).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Color(0xFF76C457), size: 7),
                            SizedBox(width: 4),
                            Text(
                              'REAL-TIME FCM',
                              style: TextStyle(color: Color(0xFF76C457), fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatItem('Total Devices', '', Icons.devices_rounded),
                      Container(width: 1, height: 32, color: const Color(0xFF334155)),
                      _buildStatItem('Customers', '', Icons.person_rounded),
                      Container(width: 1, height: 32, color: const Color(0xFF334155)),
                      _buildStatItem('Riders', '', Icons.two_wheeler_rounded),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. Quick Presets Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'QUICK TEMPLATES',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.8),
                ),
                if (_titleController.text.isNotEmpty || _messageController.text.isNotEmpty)
                  InkWell(
                    onTap: () => _applyTemplate('CUSTOM'),
                    child: const Text(
                      'Clear Fields',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTemplateChip('⚡ New APK Update', 'UPDATE', Icons.system_update_rounded),
                  const SizedBox(width: 8),
                  _buildTemplateChip('🛍️ Shop / Bazar Offer', 'OFFER', Icons.local_offer_rounded),
                  const SizedBox(width: 8),
                  _buildTemplateChip('🛵 Riders Active (15 Min)', 'RIDERS_ONLINE', Icons.two_wheeler_rounded),
                  const SizedBox(width: 8),
                  _buildTemplateChip('✏️ Blank Custom', 'CUSTOM', Icons.edit_note_rounded),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Target Audience Segmented Cards
            const Text(
              'SELECT TARGET AUDIENCE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildAudienceCard(
                    title: 'All Users',
                    subtitle: '\ Devices',
                    value: 'ALL',
                    icon: Icons.groups_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildAudienceCard(
                    title: 'Customers',
                    subtitle: '\ Devices',
                    value: 'CUSTOMERS',
                    icon: Icons.shopping_bag_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildAudienceCard(
                    title: 'Riders Only',
                    subtitle: '\ Devices',
                    value: 'RIDERS',
                    icon: Icons.two_wheeler_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 4. Notification Content Inputs
            const Text(
              'NOTIFICATION MESSAGE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Field
                  TextField(
                    controller: _titleController,
                    onChanged: (_) => setState(() {}),
                    maxLength: 65,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: 'Notification Title *',
                      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      hintText: 'e.g. ⚡ Special Weekend Offer in Melapalayam!',
                      hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                      prefixIcon: const Icon(Icons.title_rounded, color: Color(0xFF76C457), size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Message Body Field
                  TextField(
                    controller: _messageController,
                    maxLines: 3,
                    maxLength: 240,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Message Body *',
                      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      hintText: 'Type message details that will pop up on user phones...',
                      hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 40),
                        child: Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF76C457), size: 20),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Action URL Field
                  TextField(
                    controller: _urlController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      labelText: 'Tap Action URL (Optional)',
                      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      hintText: 'e.g. ',
                      hintStyle: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF0284C7), size: 20),
                      suffixIcon: actionUrl.isEmpty
                          ? TextButton(
                              onPressed: () {
                                setState(() => _urlController.text = AppConstants.appDownloadUrl);
                              },
                              child: const Text('Use APK URL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () => setState(() => _urlController.clear()),
                            ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '💡 When user taps the notification, it directly opens this download link or store page.',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 5. Realistic Android Mobile Lockscreen Live Preview
            const Text(
              'LIVE MOBILE PREVIEW (ANDROID)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF334155)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: const Color(0xFF76C457),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Center(
                              child: Text('⚡', style: TextStyle(fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'ZIPPO • Delivery • Just now',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Text(
                          'TO ',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Notification Title
                  Text(
                    title.isEmpty ? 'Notification Title will appear here' : title,
                    style: TextStyle(
                      color: title.isEmpty ? const Color(0xFF64748B) : Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Notification Body
                  Text(
                    message.isEmpty ? 'Type your message above to see a real-time mobile preview...' : message,
                    style: TextStyle(
                      color: message.isEmpty ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),

                  // Action Link Pill
                  if (actionUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.download_rounded, color: Color(0xFF38BDF8), size: 13),
                          SizedBox(width: 4),
                          Text(
                            'TAP TO OPEN / DOWNLOAD',
                            style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 6. Action Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF76C457),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: _isSending ? null : _sendBroadcast,
                icon: _isSending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _isSending ? 'Dispatching Push Alert...' : 'Broadcast Push Notification Now',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: const Color(0xFF76C457)),
              const SizedBox(width: 4),
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceCard({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _selectedTarget == value;
    return InkWell(
      onTap: () => setState(() => _selectedTarget = value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE5F6DE) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF76C457) : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? const Color(0xFF2E601B) : const Color(0xFF64748B),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isSelected ? const Color(0xFF14532D) : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF3A642B) : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateChip(String label, String type, IconData icon) {
    final isSelected = _selectedType == type;
    return ChoiceChip(
      avatar: Icon(icon, size: 15, color: isSelected ? Colors.white : const Color(0xFF475569)),
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF76C457),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF334155),
        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
        fontSize: 11.5,
      ),
      onSelected: (_) => _applyTemplate(type),
    );
  }
}
