import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/specialties/dental_not_built.dart';
import 'package:doctor_management_app/features/dental/specialties/perio/perio_today_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Dashboard cards for the dental specialty of this login. Each phase adds
/// a case; general dentists get none. A phase whose screen isn't built
/// yet gets a [DentalNotBuiltCard] pointing at its primary sidebar page,
/// so the card is honest rather than missing.
List<Widget> dentalSpecialtyCards(
  DoctorSpecialtyType? sub,
  ValueChanged<int> onNavigate,
) => switch (sub) {
  DoctorSpecialtyType.periodontist => [
    PerioTodayCard(onNavigate: onNavigate),
  ],
  DoctorSpecialtyType.endodontist => [
    DentalNotBuiltCard(
      icon: RecIcons.endo,
      title: 'Root canals',
      tab: DesktopTab.rootCanals,
      onNavigate: onNavigate,
    ),
  ],
  DoctorSpecialtyType.pediatricDentist => [
    DentalNotBuiltCard(
      icon: CruIcons.patients,
      title: 'Children',
      tab: DesktopTab.pedoChildren,
      onNavigate: onNavigate,
    ),
  ],
  DoctorSpecialtyType.oralPathologist => [
    DentalNotBuiltCard(
      icon: CruIcons.flask,
      title: 'Biopsies',
      tab: DesktopTab.biopsies,
      onNavigate: onNavigate,
    ),
  ],
  DoctorSpecialtyType.oralMedicine => [
    DentalNotBuiltCard(
      icon: RecIcons.pain,
      title: 'Lesions',
      tab: DesktopTab.oralMedLesions,
      onNavigate: onNavigate,
    ),
  ],
  DoctorSpecialtyType.dentalAnesthesiologist => [
    DentalNotBuiltCard(
      icon: CruIcons.flask,
      title: 'Sedation cases',
      tab: DesktopTab.sedationCases,
      onNavigate: onNavigate,
    ),
  ],
  DoctorSpecialtyType.prosthodontist => [
    DentalNotBuiltCard(
      icon: CruIcons.box,
      title: 'Lab cases',
      tab: DesktopTab.labCases,
      onNavigate: onNavigate,
    ),
  ],
  DoctorSpecialtyType.orthodontist => [
    DentalNotBuiltCard(
      icon: CruIcons.patients,
      title: 'Ortho patients',
      tab: DesktopTab.orthoPatients,
      onNavigate: onNavigate,
    ),
  ],
  DoctorSpecialtyType.publicHealthDentist => [
    DentalNotBuiltCard(
      icon: CruIcons.megaphone,
      title: 'Camps',
      tab: DesktopTab.healthCamps,
      onNavigate: onNavigate,
    ),
  ],
  DoctorSpecialtyType.oralSurgeon => [
    DentalNotBuiltCard(
      icon: DentalIcons.procedures,
      title: 'Surgeries',
      tab: DesktopTab.surgeries,
      onNavigate: onNavigate,
    ),
  ],
  // ADD PER-PHASE CASES HERE for the next dental sub-specialty.
  _ => const <Widget>[],
};
