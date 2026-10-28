import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/lan/device_identity.dart';
import 'package:doctor_management_app/features/files/lan/device_registry_service.dart';
import 'package:doctor_management_app/features/files/lan/lan_device_model.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Settings UI for Nearby Sharing (Task K4).
class NearbySharingSettingsCard extends ConsumerStatefulWidget {
  const NearbySharingSettingsCard({super.key});

  @override
  ConsumerState<NearbySharingSettingsCard> createState() =>
      _NearbySharingSettingsCardState();
}

class _NearbySharingSettingsCardState
    extends ConsumerState<NearbySharingSettingsCard> {
  bool _nearbyEnabled = true;
  String _deviceName = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await DeviceIdentity.instance.initialize();
    if (mounted) {
      setState(() {
        _nearbyEnabled = prefs.getBool('crudoc.lan.enabled') ?? true;
        _deviceName = DeviceIdentity.instance.deviceName;
      });
    }
  }

  Future<void> _toggleNearby(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('crudoc.lan.enabled', value);
    setState(() => _nearbyEnabled = value);
  }

  Future<void> _renameDevice() async {
    final controller = TextEditingController(text: _deviceName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename this device'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Device name',
            hintText: 'e.g. Reception PC, Dr Mehta’s Pixel',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != _deviceName) {
      await DeviceIdentity.instance.setDeviceName(newName);
      final clinicId = FilesRepository.instance.doctorId;
      final myUid = FilesRepository.instance.uid;
      if (clinicId.isNotEmpty) {
        await DeviceRegistryService.instance.ensureRegistered(
          clinicId: clinicId,
          myUid: myUid,
        );
      }
      setState(() => _deviceName = newName);
    }
  }

  Future<void> _removeDevice(LanDevice device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove “${device.name}”?'),
        content: const Text(
          'It will no longer be trusted for direct Wi-Fi transfers until registered again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final clinicId = FilesRepository.instance.doctorId;
      await DeviceRegistryService.instance.removeDevice(
        clinicId: clinicId,
        deviceId: device.id,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final clinicId = FilesRepository.instance.doctorId;
    final myUid = FilesRepository.instance.uid;
    final myDeviceId = DeviceIdentity.instance.deviceId;

    return CruCard(
      semanticLabel: 'Nearby Sharing Settings',
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nearby Sharing (Wi-Fi)', style: CruType.title),
                    const SizedBox(height: 2),
                    Text(
                      'Direct peer-to-peer file transfer on clinic Wi-Fi without uploading to the cloud.',
                      style: CruType.caption.tint(c.label2),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _nearbyEnabled,
                onChanged: _toggleNearby,
                activeTrackColor: c.accent,
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),
          const CruSeparator(),
          const SizedBox(height: CruSpace.s16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This Device Name', style: CruType.subhead.w600),
                    const SizedBox(height: 2),
                    Text(
                      _deviceName.isEmpty ? 'Loading…' : _deviceName,
                      style: CruType.text.tint(c.label),
                    ),
                  ],
                ),
              ),
              CruButton(
                label: 'Rename',
                kind: CruButtonKind.inset,
                onPressed: _renameDevice,
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),
          const CruSeparator(),
          const SizedBox(height: CruSpace.s16),
          Text('Clinic Trusted Devices', style: CruType.subhead.w600),
          const SizedBox(height: CruSpace.s8),
          StreamBuilder<List<LanDevice>>(
            stream: DeviceRegistryService.instance.watchDevices(clinicId),
            builder: (context, snapshot) {
              final devices = snapshot.data ?? const [];
              if (devices.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
                  child: Text(
                    'No other devices registered in this clinic yet.',
                    style: CruType.caption.tint(c.label3),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: devices.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final dev = devices[i];
                  final isMe = dev.id == myDeviceId;
                  final isMine = dev.uid == myUid;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      dev.platform == 'android'
                          ? Icons.phone_android
                          : Icons.computer,
                      color: isMe ? c.accent : c.label2,
                    ),
                    title: Row(
                      children: [
                        Text(dev.name, style: CruType.body.w600.tint(c.label)),
                        if (isMe) ...[
                          const SizedBox(width: CruSpace.s8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: c.accentWash,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'This device',
                              style: CruType.caption.tint(c.accentText),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      dev.hasLanEndpoint
                          ? 'Available on Wi-Fi (${dev.ips.first}:${dev.port})'
                          : 'Offline',
                      style: CruType.caption.tint(
                        dev.hasLanEndpoint ? Colors.green : c.label3,
                      ),
                    ),
                    trailing: (isMine && !isMe)
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: 'Remove',
                            onPressed: () => _removeDevice(dev),
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
