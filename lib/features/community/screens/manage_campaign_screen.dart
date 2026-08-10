import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class ManageCampaignScreen extends StatefulWidget {
  final String? institutionId;
  final String? institutionName;
  final bool isGlobal;

  const ManageCampaignScreen({
    super.key,
    this.institutionId,
    this.institutionName,
    this.isGlobal = false,
  });

  @override
  State<ManageCampaignScreen> createState() => _ManageCampaignScreenState();
}

class _ManageCampaignScreenState extends State<ManageCampaignScreen> {
  late final ApiClient _apiClient;
  bool _isLoading = true;
  bool _isSaving = false;

  final _formKey = GlobalKey<FormState>();

  bool _showBanner = false;
  final _bannerTitleCtrl = TextEditingController();
  final _bannerMessageCtrl = TextEditingController();

  bool _showPopup = false;
  final _versionIdCtrl = TextEditingController(text: "v1");
  final _popupTitleCtrl = TextEditingController();
  final _popupMessageCtrl = TextEditingController();
  String _lottieUrl =
      "https://lottie.host/df56ac6c-2b29-47e5-b390-50143a062fa8/3VG8SB4thj.json";
  String _targetRoute = "/square";

  final _themeHexCtrl = TextEditingController();

  final List<String> _routes = ['/square', '/bazaar', '/vault'];

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchCampaignData();
  }

  Future<void> _fetchCampaignData() async {
    if (widget.isGlobal) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      String endpoint = widget.institutionId != null
          ? "/api/admin/institutions/${widget.institutionId}/campaign"
          : "/api/utils/app-campaign";

      final response = await _apiClient.authenticatedRequest(
        context,
        endpoint,
        method: "GET",
      );

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _showBanner = data['show_banner'] ?? false;
          _bannerTitleCtrl.text = data['banner_title'] ?? '';
          _bannerMessageCtrl.text = data['banner_message'] ?? '';

          _showPopup = data['show_popup'] ?? false;
          _versionIdCtrl.text = data['version_id'] ?? 'v1';
          _popupTitleCtrl.text = data['popup_title'] ?? '';
          _popupMessageCtrl.text = data['popup_message'] ?? '';
          if (data['lottie_url'] != null) _lottieUrl = data['lottie_url'];
          if (data['target_route'] != null) _targetRoute = data['target_route'];

          _themeHexCtrl.text = data['primary_color_hex'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveCampaign() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      String endpoint = widget.isGlobal
          ? "/api/admin/campaign/global"
          : (widget.institutionId != null
                ? "/api/admin/institutions/${widget.institutionId}/campaign"
                : "/api/community/settings/campaign");

      final payload = {
        "show_banner": _showBanner,
        "banner_title": _bannerTitleCtrl.text.trim(),
        "banner_message": _bannerMessageCtrl.text.trim(),
        "show_popup": _showPopup,
        "version_id": _versionIdCtrl.text.trim(),
        "popup_title": _popupTitleCtrl.text.trim(),
        "popup_message": _popupMessageCtrl.text.trim(),
        "lottie_url": _lottieUrl,
        "target_route": _targetRoute,
        "primary_color_hex": _themeHexCtrl.text.trim(),
      };

      final response = await _apiClient.authenticatedRequest(
        context,
        endpoint,
        method: "PATCH",
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isGlobal
                  ? 'Overwrote all institutions globally!'
                  : 'Changes pushed to students!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        throw Exception("Failed to save changes.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isGlobal
              ? 'Global Broadcast Theme'
              : (widget.institutionName != null
                    ? 'Edit Campaign: ${widget.institutionName}'
                    : 'Campus Theme & Events'),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.isGlobal)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "WARNING: Saving this will forcefully overwrite the theme and campaigns for EVERY institution on the platform.",
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  _buildSectionTitle("App Theme Configuration"),
                  TextFormField(
                    controller: _themeHexCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Primary Color (Hex)',
                      hintText: '#4F46E5',
                      border: OutlineInputBorder(),
                      helperText: 'Leave blank to reset to default Indigo.',
                    ),
                  ),
                  const SizedBox(height: 32),

                  _buildSectionTitle("Dynamic Pinned Banner"),
                  SwitchListTile(
                    title: const Text('Show Banner on Dashboard'),
                    subtitle: const Text(
                      'Instantly pins a banner at the top of the app.',
                    ),
                    value: _showBanner,
                    onChanged: (val) => setState(() => _showBanner = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_showBanner) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bannerTitleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Banner Title',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          _showBanner && v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bannerMessageCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Banner Message',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          _showBanner && v!.isEmpty ? 'Required' : null,
                    ),
                  ],
                  const SizedBox(height: 32),

                  _buildSectionTitle("One-Time Launch Pop-up"),
                  SwitchListTile(
                    title: const Text('Enable Launch Pop-up'),
                    subtitle: const Text(
                      'Shows a modal when students open the app.',
                    ),
                    value: _showPopup,
                    onChanged: (val) => setState(() => _showPopup = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_showPopup) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "⚠️ Campaign Version ID",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            "If you want this pop-up to show up again for users who already dismissed it, change the Version ID (e.g. from v1 to v2).",
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _versionIdCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Version ID',
                              isDense: true,
                            ),
                            validator: (v) =>
                                _showPopup && v!.isEmpty ? 'Required' : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _popupTitleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Pop-up Title',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          _showPopup && v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _popupMessageCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Pop-up Message',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          _showPopup && v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _lottieUrl,
                      decoration: const InputDecoration(
                        labelText: 'Lottie Animation URL',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => _lottieUrl = val,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _targetRoute,
                      decoration: const InputDecoration(
                        labelText: 'Action Button Target Route',
                        border: OutlineInputBorder(),
                      ),
                      items: _routes
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => _targetRoute = val!),
                    ),
                  ],
                  const SizedBox(height: 48),

                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveCampaign,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: widget.isGlobal
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            widget.isGlobal
                                ? 'OVERWRITE GLOBALLY'
                                : 'Push Changes Live',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
        ),
      ),
    );
  }
}
