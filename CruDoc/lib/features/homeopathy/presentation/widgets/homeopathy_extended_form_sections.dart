import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';

/// Form section for Childhood History (General Case Sheet Q25).
class ChildhoodHistoryCard extends StatelessWidget {
  final TextEditingController natureCtrl;
  final TextEditingController habitsCtrl;
  final TextEditingController fearsCtrl;
  final TextEditingController dreamsCtrl;
  final TextEditingController relationshipsCtrl;
  final TextEditingController sensitivitiesCtrl;
  final bool isComplete;

  const ChildhoodHistoryCard({
    super.key,
    required this.natureCtrl,
    required this.habitsCtrl,
    required this.fearsCtrl,
    required this.dreamsCtrl,
    required this.relationshipsCtrl,
    required this.sensitivitiesCtrl,
    this.isComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    return HomeopathyAccordionCard(
      title: 'Childhood History (Q25)',
      subtitle: 'Nature, habits, fears, dreams & relationships in childhood',
      isComplete: isComplete,
      icon: Icons.history_edu_rounded,
      children: [
        HomeopathyFormField(
          controller: natureCtrl,
          label: '1. What was your nature as a child?',
          hint: 'e.g. Shy, bold, stubborn, quiet, obedient, playful, rebellious',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: habitsCtrl,
          label: '2. Childhood Habits & Peculiarities',
          hint: 'e.g. Thumb-sucking, nail-biting, bedwetting, head banging',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: fearsCtrl,
          label: '3. Childhood Fears & Phobias',
          hint: 'e.g. Dark, animals, ghosts, being alone, school, strangers',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: dreamsCtrl,
          label: '4. Childhood Dreams (Recurring or Frightening)',
          hint: 'e.g. Falling, monsters, losing parents, flying, exams',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: relationshipsCtrl,
          label: '5. Relationship with Parents & Siblings',
          hint: 'e.g. Pampered, neglected, strict discipline, sibling rivalry',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: sensitivitiesCtrl,
          label: '6. Childhood Sensitivities & Vulnerabilities',
          hint: 'e.g. Cried easily if scolded, sensitive to punishment, teasing',
          maxLines: 2,
        ),
      ],
    );
  }
}

/// Form section for the 15 Personality & Mental State questions (Q1–Q18).
class ExpandedMindPersonalityCard extends StatelessWidget {
  final TextEditingController upsetWorryCtrl;
  final TextEditingController fearDetailsCtrl;
  final TextEditingController introvertExtrovertCtrl;
  final TextEditingController stressHistoryCtrl;
  final TextEditingController stressCopingCtrl;
  final TextEditingController sensitivityDetailsCtrl;
  final TextEditingController fixedHabitsCtrl;
  final TextEditingController angerBodyCtrl;
  final TextEditingController disorderSensitivityCtrl;
  final TextEditingController greatestGriefCtrl;
  final TextEditingController greatestJoysCtrl;
  final TextEditingController deeplyLikedCtrl;
  final TextEditingController deeplyDislikedCtrl;
  final TextEditingController disagreeableMindCtrl;
  final TextEditingController lifeSituationCtrl;
  final bool isComplete;

  const ExpandedMindPersonalityCard({
    super.key,
    required this.upsetWorryCtrl,
    required this.fearDetailsCtrl,
    required this.introvertExtrovertCtrl,
    required this.stressHistoryCtrl,
    required this.stressCopingCtrl,
    required this.sensitivityDetailsCtrl,
    required this.fixedHabitsCtrl,
    required this.angerBodyCtrl,
    required this.disorderSensitivityCtrl,
    required this.greatestGriefCtrl,
    required this.greatestJoysCtrl,
    required this.deeplyLikedCtrl,
    required this.deeplyDislikedCtrl,
    required this.disagreeableMindCtrl,
    required this.lifeSituationCtrl,
    this.isComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    return HomeopathyAccordionCard(
      title: 'Detailed Personality & Mental State (Q1–Q18)',
      subtitle: 'Triggers, fears, coping, anger, joys & griefs',
      isComplete: isComplete,
      icon: Icons.psychology_rounded,
      children: [
        HomeopathyFormField(
          controller: upsetWorryCtrl,
          label: 'Q1. What upsets or worries you most?',
          hint: 'e.g. Injustice, failure, illness, family conflict, finance',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: fearDetailsCtrl,
          label: 'Q3. Details of Fears & Phobias',
          hint: 'Describe when fear started, what happens physically, what you do',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: introvertExtrovertCtrl,
          label: 'Q4. Introvert or Extrovert Nature',
          hint: 'Reserved vs outgoing, sharing feelings vs keeping within',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: stressHistoryCtrl,
          label: 'Q5. Major Life Stresses & Chronology',
          hint: 'Bereavement, financial loss, divorce, job loss, emotional shock',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: stressCopingCtrl,
          label: 'Q7. How do you cope when stressed or angry?',
          hint: 'Silence, weeping, shouting, isolating, walking, working, smoking',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: sensitivityDetailsCtrl,
          label: 'Q8. Sensitivities to surroundings & people',
          hint: 'Noise, bright light, odors, rude behavior, criticism, sympathy',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: fixedHabitsCtrl,
          label: 'Q9. Fixed Habits, Routines or Fastidiousness',
          hint: 'Need everything in order, checking locks repeatedly, cleanliness',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: angerBodyCtrl,
          label: 'Q10. Physical symptoms when angry',
          hint: 'Trembling, headache, palpitations, loss of speech, indigestion',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: disorderSensitivityCtrl,
          label: 'Q12. Reaction to Disorder & Untidiness',
          hint: 'Cannot tolerate mess vs messy/unconcerned',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: greatestGriefCtrl,
          label: 'Q13. Greatest Grief or Sad Event in Life',
          hint: 'Event and how it changed your health or outlook',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: greatestJoysCtrl,
          label: 'Q14. Greatest Joys or Happy Experiences',
          hint: 'What brings you genuine contentment and fulfillment',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: deeplyLikedCtrl,
          label: 'Q15. Matters or Activities Deeply Liked',
          hint: 'Music, nature, solitude, travel, books, helping others',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: deeplyDislikedCtrl,
          label: 'Q16. Matters or Actions Deeply Disliked',
          hint: 'Hypocrisy, hurry, domination, dishonesty, crowds',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: disagreeableMindCtrl,
          label: 'Q17. Most Disagreeable Aspect of Your Own Mind',
          hint: 'Overthinking, jealousy, anger, suspiciousness, impatience',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: lifeSituationCtrl,
          label: 'Q18. Overall Picture of Current Life Situation',
          hint: 'How you perceive your life right now (content, trapped, struggling, peaceful)',
          maxLines: 2,
        ),
      ],
    );
  }
}

/// Form section for the full pediatric questionnaire (Children Case Sheet Q1–Q27).
class ChildrenPediatricFormCard extends StatelessWidget {
  final TextEditingController coldHeatCtrl;
  final TextEditingController behaviorWhenUpsetCtrl;
  final TextEditingController whatMakesHappyCtrl;
  final TextEditingController schoolBehaviorCtrl;
  final TextEditingController graspingScoreCtrl;
  final TextEditingController childTypeCtrl;
  final TextEditingController vaccinationCtrl;
  final TextEditingController favoriteSportCtrl;
  final TextEditingController attitudeParentsCtrl;
  final TextEditingController medicalHistoryCtrl;
  final TextEditingController maturityCtrl;
  final TextEditingController familyProblemsCtrl;
  final TextEditingController introvertExtrovertCtrl;
  final TextEditingController independenceCtrl;
  final TextEditingController waterIntakeCtrl;
  final TextEditingController birthComplicationsCtrl;
  final TextEditingController motherPregnancyCtrl;
  final TextEditingController motherMedicalCtrl;
  final TextEditingController familyHereditaryCtrl;
  final TextEditingController walkingTeethingCtrl;
  final TextEditingController abnormalBehaviorsCtrl;
  final TextEditingController childFearsCtrl;
  final TextEditingController sleepingHabitsCtrl;
  final TextEditingController abnormalCravingsCtrl;
  final TextEditingController wormsCtrl;
  final TextEditingController headCtrl;
  final TextEditingController coughCtrl;
  final TextEditingController stomachCtrl;
  final TextEditingController stoolCtrl;
  final TextEditingController sexualAwarenessCtrl;
  final TextEditingController additionalInfoCtrl;
  final bool isComplete;

  const ChildrenPediatricFormCard({
    super.key,
    required this.coldHeatCtrl,
    required this.behaviorWhenUpsetCtrl,
    required this.whatMakesHappyCtrl,
    required this.schoolBehaviorCtrl,
    required this.graspingScoreCtrl,
    required this.childTypeCtrl,
    required this.vaccinationCtrl,
    required this.favoriteSportCtrl,
    required this.attitudeParentsCtrl,
    required this.medicalHistoryCtrl,
    required this.maturityCtrl,
    required this.familyProblemsCtrl,
    required this.introvertExtrovertCtrl,
    required this.independenceCtrl,
    required this.waterIntakeCtrl,
    required this.birthComplicationsCtrl,
    required this.motherPregnancyCtrl,
    required this.motherMedicalCtrl,
    required this.familyHereditaryCtrl,
    required this.walkingTeethingCtrl,
    required this.abnormalBehaviorsCtrl,
    required this.childFearsCtrl,
    required this.sleepingHabitsCtrl,
    required this.abnormalCravingsCtrl,
    required this.wormsCtrl,
    required this.headCtrl,
    required this.coughCtrl,
    required this.stomachCtrl,
    required this.stoolCtrl,
    required this.sexualAwarenessCtrl,
    required this.additionalInfoCtrl,
    this.isComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    return HomeopathyAccordionCard(
      title: 'Pediatric Case Sheet (Questions 1–27)',
      subtitle: 'Temperament, school, milestones, birth & developmental history',
      isComplete: isComplete,
      icon: Icons.child_care_rounded,
      initiallyExpanded: true,
      children: [
        const Text(
          'Part 1: Temperament & Mental State',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Color(0xFF0284C7),
          ),
        ),
        const SizedBox(height: 8),
        HomeopathyFormField(
          controller: coldHeatCtrl,
          label: 'Q3. Child Sensitive to Cold or Heat?',
          hint: 'Prefers warm clothing, throws off blankets, seeks AC/fan, catches cold easily',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: behaviorWhenUpsetCtrl,
          label: 'Q4. Behavior when upset, scolded or crying',
          hint: 'Tantrums, throwing things, sulking in corner, wants to be carried/rocked',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: whatMakesHappyCtrl,
          label: 'Q5. What makes the child happy & calm?',
          hint: 'Music, play, affection, outdoors, storytelling, sweets',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: schoolBehaviorCtrl,
          label: 'Q6. School Behavior, Studies & Friends',
          hint: 'Attentive, restless, fights with peers, fear of teachers, exam anxiety',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: HomeopathyFormField(
                controller: graspingScoreCtrl,
                label: 'Q7. Grasping Score (1-10)',
                hint: '1 to 10',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HomeopathyFormField(
                controller: childTypeCtrl,
                label: 'Q8. Child Type / Build',
                hint: 'Chubby, lean, tall, delicate, flabby',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: attitudeParentsCtrl,
          label: 'Q11. Attitude towards parents & siblings',
          hint: 'Obedient, stubborn, jealous of younger sibling, clinging to mother',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: familyProblemsCtrl,
          label: 'Q14. Reaction to family arguments or tension',
          hint: 'Frightened, cries, becomes aggressive, physical complaints follow',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: HomeopathyFormField(
                controller: introvertExtrovertCtrl,
                label: 'Q15. Introvert / Extrovert',
                hint: 'Shy with strangers vs friendly',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HomeopathyFormField(
                controller: independenceCtrl,
                label: 'Q16. Independence Level',
                hint: 'Self-reliant vs dependent',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        const Text(
          'Part 2: Birth, Pregnancy & Developmental Milestones',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Color(0xFF0284C7),
          ),
        ),
        const SizedBox(height: 8),
        HomeopathyFormField(
          controller: birthComplicationsCtrl,
          label: 'Q18. Birth Complications (Forceps, Caesarean, Jaundice, Delayed Cry)',
          hint: 'Full term / premature, birth weight, ICU stay',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: motherPregnancyCtrl,
          label: 'Q19. Mother\'s Emotional State & Health during Pregnancy',
          hint: 'Grief, shock, nausea, high BP, thyroid, family stress during pregnancy',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: motherMedicalCtrl,
          label: 'Q20. Mother\'s Medical History & Medications',
          hint: 'Hormones, antibiotics taken, prior miscarriages',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: familyHereditaryCtrl,
          label: 'Q21. Family Hereditary Tendencies',
          hint: 'Asthma, allergies, eczema, diabetes, cancer, TB in bloodline',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: walkingTeethingCtrl,
          label: 'Q22. Milestone Ages (Walking, Talking, Teething)',
          hint: 'Teething troubles (fever/diarrhea), delayed speech, delayed walking',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: vaccinationCtrl,
          label: 'Q9. Vaccination History & Adverse Reactions',
          hint: 'High fever, convulsions, skin eruption, regressions after vaccine',
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        const Text(
          'Part 3: Habits, Fears, Cravings & Organ Checks',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Color(0xFF0284C7),
          ),
        ),
        const SizedBox(height: 8),
        HomeopathyFormField(
          controller: abnormalBehaviorsCtrl,
          label: 'Q23. Abnormal Behaviors (Head banging, biting, picking nose/lips)',
          hint: 'Tics, restlessness, bedwetting, stammering',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: childFearsCtrl,
          label: 'Q24. Child Fears (Dogs, dark, thunder, strangers, being alone)',
          hint: 'Describe specific fears and child\'s reaction',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: sleepingHabitsCtrl,
          label: 'Q25. Sleeping Habits (Posture, snoring, teeth grinding, sweat)',
          hint: 'Sleeps on tummy, head sweats during sleep, night terrors',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: abnormalCravingsCtrl,
          label: 'Q26. Abnormal Cravings (Mud, chalk, ice, pencil, salt, coal)',
          hint: 'Pica tendencies or unusual food desires',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: wormsCtrl,
          label: 'Q27. Worms History & Symptoms',
          hint: 'Anal itching, nose rubbing, grinds teeth at night, variable appetite',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: headCtrl,
          label: 'Head, Eyes, Nose & Throat Symptoms',
          hint: 'Frequent cold, tonsils, adenoids, ear infections',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: coughCtrl,
          label: 'Cough, Asthma & Chest Respiration',
          hint: 'Wheezing, night cough, recurrent bronchitis',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: stomachCtrl,
          label: 'Stomach, Appetite & Digestion',
          hint: 'Vomiting milk, colic, poor appetite vs ravenous hunger',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: stoolCtrl,
          label: 'Stool & Urinary Symptoms',
          hint: 'Constipation, hard large stool, involuntary urination, enuresis',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: sexualAwarenessCtrl,
          label: 'Age-Appropriate Sexual Awareness / Habits',
          hint: 'Genital touching, masturbation tendencies in toddler/child',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: additionalInfoCtrl,
          label: 'Additional Information from Parents / Caregivers',
          hint: 'Any other unique observation about the child',
          maxLines: 2,
        ),
      ],
    );
  }
}

/// Form section for Female & Endocrine Questionnaire (Thyroid, Hormonal, Life Stages).
class FemaleEndocrineFormCard extends StatelessWidget {
  final TextEditingController diagnosisCtrl;
  final TextEditingController howStartedCtrl;
  final TextEditingController physioTriggerCtrl;
  final TextEditingController emotionalTriggerCtrl;
  final TextEditingController manifestationLocCtrl;
  final TextEditingController otherOrgansCtrl;
  final TextEditingController goitreCtrl;
  final TextEditingController glandsCtrl;
  final TextEditingController skinCtrl;
  final TextEditingController cardiacCtrl;
  final TextEditingController stagesOfLifeCtrl;
  final TextEditingController menstrualCtrl;
  final TextEditingController weaknessCtrl;
  final TextEditingController relationshipsCtrl;
  final bool isComplete;

  const FemaleEndocrineFormCard({
    super.key,
    required this.diagnosisCtrl,
    required this.howStartedCtrl,
    required this.physioTriggerCtrl,
    required this.emotionalTriggerCtrl,
    required this.manifestationLocCtrl,
    required this.otherOrgansCtrl,
    required this.goitreCtrl,
    required this.glandsCtrl,
    required this.skinCtrl,
    required this.cardiacCtrl,
    required this.stagesOfLifeCtrl,
    required this.menstrualCtrl,
    required this.weaknessCtrl,
    required this.relationshipsCtrl,
    this.isComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    return HomeopathyAccordionCard(
      title: 'Female & Endocrine Questionnaire',
      subtitle: 'Thyroid, hormonal etiology, lifecycle stages & systemic symptoms',
      isComplete: isComplete,
      icon: Icons.female_rounded,
      initiallyExpanded: true,
      children: [
        HomeopathyFormField(
          controller: diagnosisCtrl,
          label: 'Medical Diagnosis & Thyroid Profile',
          hint: 'e.g. Hypothyroidism, Hashimoto\'s, Graves\', PCOD, Goitre, TSH/T3/T4 values',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: howStartedCtrl,
          label: 'How & When Did the Problem Start?',
          hint: 'Initial symptoms noticed, timeline, precipitating circumstances',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: physioTriggerCtrl,
          label: 'Physiological Triggers (Menarche, Pregnancy, OC Pills, Hysterectomy)',
          hint: 'Did complaint trigger after puberty, miscarriage, childbirth, birth control pills?',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: emotionalTriggerCtrl,
          label: 'Emotional Triggers (Grief, Humiliation, Suppressed Anger)',
          hint: 'Endocrine onset linked to grief, marital stress, suppression',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: manifestationLocCtrl,
          label: 'Disease Manifestation & Physical Location',
          hint: 'General myxoedema, localized swelling, exophthalmos, puffiness around eyes',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: goitreCtrl,
          label: 'Goitre / Thyroid Gland Details',
          hint: 'Size, texture (soft/hard/nodular), constriction feeling, choking sensation with collar',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: glandsCtrl,
          label: 'Glandular Problems (Lymph, Salivary, Mammary)',
          hint: 'Breast tenderness, swollen lymph nodes, parotid enlargement',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: skinCtrl,
          label: 'Skin & Hair Symptoms (Dryness, Hair Loss, Pigmentation)',
          hint: 'Loss of outer eyebrow hair, coarse skin, brittle nails, melasma',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: cardiacCtrl,
          label: 'Cardiac & Circulatory Symptoms (Palpitations, BP, Flushes)',
          hint: 'Hot flashes, racing pulse, postural dizziness, swollen ankles',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: weaknessCtrl,
          label: 'Physical & Mental Weakness / Lethargy',
          hint: 'Fatigue on waking, brain fog, apathy, sluggishness',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: stagesOfLifeCtrl,
          label: 'Stages of Life Impact (Puberty / Motherhood / Menopause)',
          hint: 'How health fluctuated during childhood, puberty, post-pregnancy, and perimenopause',
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: menstrualCtrl,
          label: 'Menstrual & Hormonal Cycle Details',
          hint: 'Cycle length, flow amount, clots, PMS mood swings, spotting',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: relationshipsCtrl,
          label: 'Relationships & Domestic Dynamics (Family / In-Laws / Work)',
          hint: 'Interpersonal tensions, feelings of being unappreciated or suppressed',
          maxLines: 2,
        ),
      ],
    );
  }
}

/// Form section for the short-form Acute Case Sheet (fever, acute modals, quick matrix).
class AcuteCaseSheetCard extends StatelessWidget {
  final TextEditingController complaintCtrl;
  final TextEditingController causeCtrl;
  final TextEditingController worseCtrl;
  final TextEditingController betterCtrl;
  final TextEditingController mentalConditionCtrl;
  final TextEditingController waterReqCtrl;
  final TextEditingController sweatCtrl;
  final TextEditingController postureCtrl;
  final TextEditingController feverCtrl;
  final TextEditingController coughCtrl;
  final TextEditingController looseDryCoughCtrl;
  final TextEditingController diarrheaCtrl;
  final TextEditingController painCtrl;
  final TextEditingController uncommonSymptomsCtrl;
  final TextEditingController additionalInfoCtrl;
  final bool isComplete;

  const AcuteCaseSheetCard({
    super.key,
    required this.complaintCtrl,
    required this.causeCtrl,
    required this.worseCtrl,
    required this.betterCtrl,
    required this.mentalConditionCtrl,
    required this.waterReqCtrl,
    required this.sweatCtrl,
    required this.postureCtrl,
    required this.feverCtrl,
    required this.coughCtrl,
    required this.looseDryCoughCtrl,
    required this.diarrheaCtrl,
    required this.painCtrl,
    required this.uncommonSymptomsCtrl,
    required this.additionalInfoCtrl,
    this.isComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    return HomeopathyAccordionCard(
      title: 'Acute Presentation Questionnaire',
      subtitle: 'Onset, modalities, fever stages, thirst, posture & acute totality',
      isComplete: isComplete,
      icon: Icons.flash_on_rounded,
      initiallyExpanded: true,
      children: [
        HomeopathyFormField(
          controller: complaintCtrl,
          label: 'Q3. Detailed Acute Complaint (What exactly is happening?)',
          hint: 'e.g. Sudden high fever with bodyache, barking cough, acute diarrhea',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: causeCtrl,
          label: 'Q4. Cause of Present Complaint (Trigger)',
          hint: 'e.g. Cold dry wind, getting wet in rain, ice cream, mental shock, anger, overexertion',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: HomeopathyFormField(
                controller: worseCtrl,
                label: 'Q6. What Makes It Worse? (<)',
                hint: 'Cold air, motion, light, night, touch',
                maxLines: 2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HomeopathyFormField(
                controller: betterCtrl,
                label: 'Q7. What Makes It Better? (>)',
                hint: 'Warmth, rest, pressure, hot drink',
                maxLines: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: mentalConditionCtrl,
          label: 'Q8. Mental Condition During This Suffering',
          hint: 'Restless & anxious (Acon/Ars), irritable & wants silence (Bry/Cham), weeping & clingy (Puls)',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: HomeopathyFormField(
                controller: waterReqCtrl,
                label: 'Q10. Water Requirement (Thirst)',
                hint: 'Thirstless / Large quantities / Sips often',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HomeopathyFormField(
                controller: sweatCtrl,
                label: 'Q11. Sweat Details (Stages, odour)',
                hint: 'Profuse, offensive, stains yellow, on head only',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: postureCtrl,
          label: 'Q12. Posture Modalities (How patient lies/sits)',
          hint: 'Must sit up to breathe, lies on painful side, double up with hands on abdomen',
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: feverCtrl,
          label: 'Q15. Fever Details (Chill, Heat, Sweat Sequence)',
          hint: 'Time of chill (e.g. 10 AM), thirst during chill or heat, shivering with goosebumps',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: HomeopathyFormField(
                controller: coughCtrl,
                label: 'Q17. Cough & Chest Details',
                hint: 'Dry racking vs loose rattling',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HomeopathyFormField(
                controller: looseDryCoughCtrl,
                label: 'Q19. Taste / Sputum Character',
                hint: 'Salty, bitter, sweet, yellow, green',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: diarrheaCtrl,
          label: 'Q20. Stool / Diarrhea / Dysentery Character',
          hint: 'Watery, offensive, bloody, painless, burning, urgency on waking',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: painCtrl,
          label: 'Q21. Body Pain Character & Location',
          hint: 'Aching all over bones (Eup-per), sharp stitching (Bry), burning (Ars)',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: uncommonSymptomsCtrl,
          label: 'Q16. Peculiar or Uncommon Symptoms Noticed',
          hint: 'e.g. Red face during chill, appetite ravenous during fever',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        HomeopathyFormField(
          controller: additionalInfoCtrl,
          label: 'Q22. Any Additional Information for Remedy Selection',
          hint: 'Any other sudden changes in sleep, mood, or urination',
          maxLines: 2,
        ),
      ],
    );
  }
}

/// Controller bundle for all extended homeopathy questionnaire sections.
class ExtendedCaseSheetControllers {
  // Childhood History (Q25)
  final TextEditingController childhoodNatureCtrl;
  final TextEditingController childhoodHabitsCtrl;
  final TextEditingController childhoodFearsCtrl;
  final TextEditingController childhoodDreamsHistoryCtrl;
  final TextEditingController childhoodRelationshipsCtrl;
  final TextEditingController childhoodSensitivitiesCtrl;

  // Expanded Mind Q1-Q18
  final TextEditingController upsetWorryCtrl;
  final TextEditingController fearDetailsCtrl;
  final TextEditingController introvertExtrovertCtrl;
  final TextEditingController stressHistoryCtrl;
  final TextEditingController stressCopingCtrl;
  final TextEditingController sensitivityDetailsCtrl;
  final TextEditingController fixedHabitsCtrl;
  final TextEditingController angerBodyCtrl;
  final TextEditingController disorderSensitivityCtrl;
  final TextEditingController greatestGriefCtrl;
  final TextEditingController greatestJoysCtrl;
  final TextEditingController deeplyLikedCtrl;
  final TextEditingController deeplyDislikedCtrl;
  final TextEditingController disagreeableMindCtrl;
  final TextEditingController lifeSituationCtrl;

  // Pediatric Q1-Q27
  final TextEditingController childColdHeatCtrl;
  final TextEditingController childBehaviorUpsetCtrl;
  final TextEditingController childWhatMakesHappyCtrl;
  final TextEditingController childSchoolBehaviorCtrl;
  final TextEditingController childGraspingScoreCtrl;
  final TextEditingController childTypeCtrl;
  final TextEditingController childVaccinationCtrl;
  final TextEditingController childFavoriteSportCtrl;
  final TextEditingController childAttitudeParentsCtrl;
  final TextEditingController childMedicalHistoryCtrl;
  final TextEditingController childMaturityCtrl;
  final TextEditingController childFamilyProblemsCtrl;
  final TextEditingController childIntrovertCtrl;
  final TextEditingController childIndependenceCtrl;
  final TextEditingController childWaterIntakeCtrl;
  final TextEditingController childBirthComplicationsCtrl;
  final TextEditingController childMotherPregnancyCtrl;
  final TextEditingController childMotherMedicalCtrl;
  final TextEditingController childFamilyHereditaryCtrl;
  final TextEditingController childWalkingTeethingCtrl;
  final TextEditingController childAbnormalBehaviorsCtrl;
  final TextEditingController childFearsSpecificCtrl;
  final TextEditingController childSleepingHabitsCtrl;
  final TextEditingController abnormalCravingsCtrl;
  final TextEditingController childWormsCtrl;
  final TextEditingController childHeadCtrl;
  final TextEditingController childCoughAsthmaCtrl;
  final TextEditingController childStomachCtrl;
  final TextEditingController childStoolRectumCtrl;
  final TextEditingController childSexualAwarenessCtrl;
  final TextEditingController childAdditionalInfoCtrl;

  // Female & Endocrine
  final TextEditingController endoDiagnosisCtrl;
  final TextEditingController endoHowStartedCtrl;
  final TextEditingController endoPhysioTriggerCtrl;
  final TextEditingController endoEmotionalTriggerCtrl;
  final TextEditingController endoManifestationLocCtrl;
  final TextEditingController endoOtherOrgansCtrl;
  final TextEditingController endoGoitreCtrl;
  final TextEditingController endoGlandsCtrl;
  final TextEditingController endoSkinCtrl;
  final TextEditingController endoCardiacCtrl;
  final TextEditingController endoStagesOfLifeCtrl;
  final TextEditingController endoMenstrualCtrl;
  final TextEditingController endoWeaknessCtrl;
  final TextEditingController endoRelationshipsCtrl;

  // Acute
  final TextEditingController acuteComplaintCtrl;
  final TextEditingController acuteCauseCtrl;
  final TextEditingController acuteWorseCtrl;
  final TextEditingController acuteBetterCtrl;
  final TextEditingController acuteMentalConditionCtrl;
  final TextEditingController acuteWaterReqCtrl;
  final TextEditingController acuteSweatCtrl;
  final TextEditingController acutePostureCtrl;
  final TextEditingController acuteFeverCtrl;
  final TextEditingController acuteCoughCtrl;
  final TextEditingController acuteLooseDryCoughCtrl;
  final TextEditingController acuteDiarrheaCtrl;
  final TextEditingController acutePainCtrl;
  final TextEditingController acuteUncommonSymptomsCtrl;
  final TextEditingController acuteAdditionalInfoCtrl;

  // Expanded Generals & Sleep
  final TextEditingController hungerTimeCtrl;
  final TextEditingController hungerReactionCtrl;
  final TextEditingController eatingSpeedCtrl;
  final TextEditingController thirstTimeCtrl;
  final TextEditingController tasteChangesCtrl;
  final TextEditingController sleepPostureCtrl;
  final TextEditingController sleepRestrictionsCtrl;
  final TextEditingController sleepBehaviorsCtrl;
  final TextEditingController childhoodDreamsCtrl;

  ExtendedCaseSheetControllers._({
    required this.childhoodNatureCtrl,
    required this.childhoodHabitsCtrl,
    required this.childhoodFearsCtrl,
    required this.childhoodDreamsHistoryCtrl,
    required this.childhoodRelationshipsCtrl,
    required this.childhoodSensitivitiesCtrl,
    required this.upsetWorryCtrl,
    required this.fearDetailsCtrl,
    required this.introvertExtrovertCtrl,
    required this.stressHistoryCtrl,
    required this.stressCopingCtrl,
    required this.sensitivityDetailsCtrl,
    required this.fixedHabitsCtrl,
    required this.angerBodyCtrl,
    required this.disorderSensitivityCtrl,
    required this.greatestGriefCtrl,
    required this.greatestJoysCtrl,
    required this.deeplyLikedCtrl,
    required this.deeplyDislikedCtrl,
    required this.disagreeableMindCtrl,
    required this.lifeSituationCtrl,
    required this.childColdHeatCtrl,
    required this.childBehaviorUpsetCtrl,
    required this.childWhatMakesHappyCtrl,
    required this.childSchoolBehaviorCtrl,
    required this.childGraspingScoreCtrl,
    required this.childTypeCtrl,
    required this.childVaccinationCtrl,
    required this.childFavoriteSportCtrl,
    required this.childAttitudeParentsCtrl,
    required this.childMedicalHistoryCtrl,
    required this.childMaturityCtrl,
    required this.childFamilyProblemsCtrl,
    required this.childIntrovertCtrl,
    required this.childIndependenceCtrl,
    required this.childWaterIntakeCtrl,
    required this.childBirthComplicationsCtrl,
    required this.childMotherPregnancyCtrl,
    required this.childMotherMedicalCtrl,
    required this.childFamilyHereditaryCtrl,
    required this.childWalkingTeethingCtrl,
    required this.childAbnormalBehaviorsCtrl,
    required this.childFearsSpecificCtrl,
    required this.childSleepingHabitsCtrl,
    required this.abnormalCravingsCtrl,
    required this.childWormsCtrl,
    required this.childHeadCtrl,
    required this.childCoughAsthmaCtrl,
    required this.childStomachCtrl,
    required this.childStoolRectumCtrl,
    required this.childSexualAwarenessCtrl,
    required this.childAdditionalInfoCtrl,
    required this.endoDiagnosisCtrl,
    required this.endoHowStartedCtrl,
    required this.endoPhysioTriggerCtrl,
    required this.endoEmotionalTriggerCtrl,
    required this.endoManifestationLocCtrl,
    required this.endoOtherOrgansCtrl,
    required this.endoGoitreCtrl,
    required this.endoGlandsCtrl,
    required this.endoSkinCtrl,
    required this.endoCardiacCtrl,
    required this.endoStagesOfLifeCtrl,
    required this.endoMenstrualCtrl,
    required this.endoWeaknessCtrl,
    required this.endoRelationshipsCtrl,
    required this.acuteComplaintCtrl,
    required this.acuteCauseCtrl,
    required this.acuteWorseCtrl,
    required this.acuteBetterCtrl,
    required this.acuteMentalConditionCtrl,
    required this.acuteWaterReqCtrl,
    required this.acuteSweatCtrl,
    required this.acutePostureCtrl,
    required this.acuteFeverCtrl,
    required this.acuteCoughCtrl,
    required this.acuteLooseDryCoughCtrl,
    required this.acuteDiarrheaCtrl,
    required this.acutePainCtrl,
    required this.acuteUncommonSymptomsCtrl,
    required this.acuteAdditionalInfoCtrl,
    required this.hungerTimeCtrl,
    required this.hungerReactionCtrl,
    required this.eatingSpeedCtrl,
    required this.thirstTimeCtrl,
    required this.tasteChangesCtrl,
    required this.sleepPostureCtrl,
    required this.sleepRestrictionsCtrl,
    required this.sleepBehaviorsCtrl,
    required this.childhoodDreamsCtrl,
  });

  factory ExtendedCaseSheetControllers.fromSheet(HomeopathyCaseSheet s) {
    return ExtendedCaseSheetControllers._(
      childhoodNatureCtrl:
          TextEditingController(text: s.childhoodHistory.childhoodNature),
      childhoodHabitsCtrl:
          TextEditingController(text: s.childhoodHistory.childhoodHabits),
      childhoodFearsCtrl:
          TextEditingController(text: s.childhoodHistory.childhoodFears),
      childhoodDreamsHistoryCtrl:
          TextEditingController(text: s.childhoodHistory.childhoodDreams),
      childhoodRelationshipsCtrl:
          TextEditingController(text: s.childhoodHistory.childhoodRelationships),
      childhoodSensitivitiesCtrl:
          TextEditingController(text: s.childhoodHistory.childhoodSensitivities),
      upsetWorryCtrl:
          TextEditingController(text: s.mentalEmotional.upsetWorryTriggers),
      fearDetailsCtrl:
          TextEditingController(text: s.mentalEmotional.fearDetails),
      introvertExtrovertCtrl:
          TextEditingController(text: s.mentalEmotional.introvertExtrovert),
      stressHistoryCtrl:
          TextEditingController(text: s.mentalEmotional.stressHistory),
      stressCopingCtrl:
          TextEditingController(text: s.mentalEmotional.stressCopingMethods),
      sensitivityDetailsCtrl:
          TextEditingController(text: s.mentalEmotional.sensitivityDetails),
      fixedHabitsCtrl:
          TextEditingController(text: s.mentalEmotional.fixedHabits),
      angerBodyCtrl:
          TextEditingController(text: s.mentalEmotional.angerBodySymptoms),
      disorderSensitivityCtrl:
          TextEditingController(text: s.mentalEmotional.disorderSensitivity),
      greatestGriefCtrl:
          TextEditingController(text: s.mentalEmotional.greatestGrief),
      greatestJoysCtrl:
          TextEditingController(text: s.mentalEmotional.greatestJoys),
      deeplyLikedCtrl:
          TextEditingController(text: s.mentalEmotional.deeplyLikedActivities),
      deeplyDislikedCtrl:
          TextEditingController(text: s.mentalEmotional.deeplyDislikedMatters),
      disagreeableMindCtrl:
          TextEditingController(text: s.mentalEmotional.disagreeableMindAspects),
      lifeSituationCtrl:
          TextEditingController(text: s.mentalEmotional.lifeSituationPicture),
      childColdHeatCtrl:
          TextEditingController(text: s.childrenCaseSheet.coldOrHeatSensitive),
      childBehaviorUpsetCtrl:
          TextEditingController(text: s.childrenCaseSheet.behaviorWhenUpset),
      childWhatMakesHappyCtrl:
          TextEditingController(text: s.childrenCaseSheet.whatMakesHappy),
      childSchoolBehaviorCtrl:
          TextEditingController(text: s.childrenCaseSheet.schoolBehavior),
      childGraspingScoreCtrl: TextEditingController(
          text: s.childrenCaseSheet.graspingIntelligenceScore > 0
              ? s.childrenCaseSheet.graspingIntelligenceScore.toString()
              : ''),
      childTypeCtrl:
          TextEditingController(text: s.childrenCaseSheet.childTypeDescription),
      childVaccinationCtrl:
          TextEditingController(text: s.childrenCaseSheet.vaccinationHistory),
      childFavoriteSportCtrl:
          TextEditingController(text: s.childrenCaseSheet.favoriteSportActivity),
      childAttitudeParentsCtrl:
          TextEditingController(text: s.childrenCaseSheet.attitudeToParents),
      childMedicalHistoryCtrl:
          TextEditingController(text: s.childrenCaseSheet.childMedicalHistory),
      childMaturityCtrl:
          TextEditingController(text: s.childrenCaseSheet.maturityLevel),
      childFamilyProblemsCtrl:
          TextEditingController(text: s.childrenCaseSheet.familyProblemsReaction),
      childIntrovertCtrl:
          TextEditingController(text: s.childrenCaseSheet.childIntrovertExtrovert),
      childIndependenceCtrl:
          TextEditingController(text: s.childrenCaseSheet.independenceLevel),
      childWaterIntakeCtrl:
          TextEditingController(text: s.childrenCaseSheet.dailyWaterIntake),
      childBirthComplicationsCtrl:
          TextEditingController(text: s.childrenCaseSheet.birthComplications),
      childMotherPregnancyCtrl:
          TextEditingController(text: s.childrenCaseSheet.motherPregnancyHistory),
      childMotherMedicalCtrl:
          TextEditingController(text: s.childrenCaseSheet.motherMedicalHistory),
      childFamilyHereditaryCtrl:
          TextEditingController(text: s.childrenCaseSheet.familyHealthHereditary),
      childWalkingTeethingCtrl:
          TextEditingController(text: s.childrenCaseSheet.walkingTeethingAge),
      childAbnormalBehaviorsCtrl:
          TextEditingController(text: s.childrenCaseSheet.abnormalBehaviors),
      childFearsSpecificCtrl:
          TextEditingController(text: s.childrenCaseSheet.childFears),
      childSleepingHabitsCtrl:
          TextEditingController(text: s.childrenCaseSheet.childSleepingHabits),
      abnormalCravingsCtrl:
          TextEditingController(text: s.childrenCaseSheet.abnormalCravings),
      childWormsCtrl:
          TextEditingController(text: s.childrenCaseSheet.wormsProblems),
      childHeadCtrl:
          TextEditingController(text: s.childrenCaseSheet.headSymptoms),
      childCoughAsthmaCtrl:
          TextEditingController(text: s.childrenCaseSheet.coughAsthmaDetails),
      childStomachCtrl:
          TextEditingController(text: s.childrenCaseSheet.stomachSymptoms),
      childStoolRectumCtrl:
          TextEditingController(text: s.childrenCaseSheet.stoolRectumSymptoms),
      childSexualAwarenessCtrl:
          TextEditingController(text: s.childrenCaseSheet.sexualAwareness),
      childAdditionalInfoCtrl:
          TextEditingController(text: s.childrenCaseSheet.additionalChildInfo),
      endoDiagnosisCtrl:
          TextEditingController(text: s.femaleEndocrine.medicalDiagnosis),
      endoHowStartedCtrl:
          TextEditingController(text: s.femaleEndocrine.howAndWhenStarted),
      endoPhysioTriggerCtrl: TextEditingController(
          text: s.femaleEndocrine.physiologicalCauseTrigger),
      endoEmotionalTriggerCtrl:
          TextEditingController(text: s.femaleEndocrine.emotionalTriggers),
      endoManifestationLocCtrl: TextEditingController(
          text: s.femaleEndocrine.diseaseManifestationLocation),
      endoOtherOrgansCtrl:
          TextEditingController(text: s.femaleEndocrine.otherOrgansInvolved),
      endoGoitreCtrl:
          TextEditingController(text: s.femaleEndocrine.goitreDetails),
      endoGlandsCtrl:
          TextEditingController(text: s.femaleEndocrine.glandsProblems),
      endoSkinCtrl:
          TextEditingController(text: s.femaleEndocrine.skinSymptoms),
      endoCardiacCtrl: TextEditingController(
          text: s.femaleEndocrine.cardiacCirculatorySymptoms),
      endoStagesOfLifeCtrl:
          TextEditingController(text: s.femaleEndocrine.stagesOfLife),
      endoMenstrualCtrl:
          TextEditingController(text: s.femaleEndocrine.menstrualHistory),
      endoWeaknessCtrl:
          TextEditingController(text: s.femaleEndocrine.physicalWeakness),
      endoRelationshipsCtrl:
          TextEditingController(text: s.femaleEndocrine.relationshipDetails),
      acuteComplaintCtrl:
          TextEditingController(text: s.acuteSheet.detailedComplaint),
      acuteCauseCtrl:
          TextEditingController(text: s.acuteSheet.causeOfComplaint),
      acuteWorseCtrl:
          TextEditingController(text: s.acuteSheet.whatMakesWorse),
      acuteBetterCtrl:
          TextEditingController(text: s.acuteSheet.whatMakesBetter),
      acuteMentalConditionCtrl: TextEditingController(
          text: s.acuteSheet.mentalConditionDuringSuffering),
      acuteWaterReqCtrl:
          TextEditingController(text: s.acuteSheet.waterRequirement),
      acuteSweatCtrl:
          TextEditingController(text: s.acuteSheet.sweatDetails),
      acutePostureCtrl:
          TextEditingController(text: s.acuteSheet.postureModalities),
      acuteFeverCtrl:
          TextEditingController(text: s.acuteSheet.acuteFeverDetails),
      acuteCoughCtrl:
          TextEditingController(text: s.acuteSheet.coughRespirationDetail),
      acuteLooseDryCoughCtrl:
          TextEditingController(text: s.acuteSheet.looseDryCoughDetails),
      acuteDiarrheaCtrl:
          TextEditingController(text: s.acuteSheet.diarrheaConstipationDetails),
      acutePainCtrl:
          TextEditingController(text: s.acuteSheet.bodyPainDetails),
      acuteUncommonSymptomsCtrl:
          TextEditingController(text: s.acuteSheet.specialUncommonSymptoms),
      acuteAdditionalInfoCtrl:
          TextEditingController(text: s.acuteSheet.additionalInfo),
      hungerTimeCtrl:
          TextEditingController(text: s.generalSymptoms.hungerTime),
      hungerReactionCtrl:
          TextEditingController(text: s.generalSymptoms.hungerReaction),
      eatingSpeedCtrl:
          TextEditingController(text: s.generalSymptoms.eatingSpeed),
      thirstTimeCtrl:
          TextEditingController(text: s.generalSymptoms.thirstTime),
      tasteChangesCtrl:
          TextEditingController(text: s.generalSymptoms.tasteChanges),
      sleepPostureCtrl:
          TextEditingController(text: s.dreamsSleep.sleepPosture),
      sleepRestrictionsCtrl:
          TextEditingController(text: s.dreamsSleep.sleepPositionRestrictions),
      sleepBehaviorsCtrl:
          TextEditingController(text: s.dreamsSleep.sleepBehaviors),
      childhoodDreamsCtrl:
          TextEditingController(text: s.dreamsSleep.childhoodDreams),
    );
  }

  void populateFromSheet(HomeopathyCaseSheet s) {
    childhoodNatureCtrl.text = s.childhoodHistory.childhoodNature;
    childhoodHabitsCtrl.text = s.childhoodHistory.childhoodHabits;
    childhoodFearsCtrl.text = s.childhoodHistory.childhoodFears;
    childhoodDreamsHistoryCtrl.text = s.childhoodHistory.childhoodDreams;
    childhoodRelationshipsCtrl.text = s.childhoodHistory.childhoodRelationships;
    childhoodSensitivitiesCtrl.text = s.childhoodHistory.childhoodSensitivities;
    upsetWorryCtrl.text = s.mentalEmotional.upsetWorryTriggers;
    fearDetailsCtrl.text = s.mentalEmotional.fearDetails;
    introvertExtrovertCtrl.text = s.mentalEmotional.introvertExtrovert;
    stressHistoryCtrl.text = s.mentalEmotional.stressHistory;
    stressCopingCtrl.text = s.mentalEmotional.stressCopingMethods;
    sensitivityDetailsCtrl.text = s.mentalEmotional.sensitivityDetails;
    fixedHabitsCtrl.text = s.mentalEmotional.fixedHabits;
    angerBodyCtrl.text = s.mentalEmotional.angerBodySymptoms;
    disorderSensitivityCtrl.text = s.mentalEmotional.disorderSensitivity;
    greatestGriefCtrl.text = s.mentalEmotional.greatestGrief;
    greatestJoysCtrl.text = s.mentalEmotional.greatestJoys;
    deeplyLikedCtrl.text = s.mentalEmotional.deeplyLikedActivities;
    deeplyDislikedCtrl.text = s.mentalEmotional.deeplyDislikedMatters;
    disagreeableMindCtrl.text = s.mentalEmotional.disagreeableMindAspects;
    lifeSituationCtrl.text = s.mentalEmotional.lifeSituationPicture;
    childColdHeatCtrl.text = s.childrenCaseSheet.coldOrHeatSensitive;
    childBehaviorUpsetCtrl.text = s.childrenCaseSheet.behaviorWhenUpset;
    childWhatMakesHappyCtrl.text = s.childrenCaseSheet.whatMakesHappy;
    childSchoolBehaviorCtrl.text = s.childrenCaseSheet.schoolBehavior;
    childGraspingScoreCtrl.text = s.childrenCaseSheet.graspingIntelligenceScore > 0
        ? s.childrenCaseSheet.graspingIntelligenceScore.toString()
        : '';
    childTypeCtrl.text = s.childrenCaseSheet.childTypeDescription;
    childVaccinationCtrl.text = s.childrenCaseSheet.vaccinationHistory;
    childFavoriteSportCtrl.text = s.childrenCaseSheet.favoriteSportActivity;
    childAttitudeParentsCtrl.text = s.childrenCaseSheet.attitudeToParents;
    childMedicalHistoryCtrl.text = s.childrenCaseSheet.childMedicalHistory;
    childMaturityCtrl.text = s.childrenCaseSheet.maturityLevel;
    childFamilyProblemsCtrl.text = s.childrenCaseSheet.familyProblemsReaction;
    childIntrovertCtrl.text = s.childrenCaseSheet.childIntrovertExtrovert;
    childIndependenceCtrl.text = s.childrenCaseSheet.independenceLevel;
    childWaterIntakeCtrl.text = s.childrenCaseSheet.dailyWaterIntake;
    childBirthComplicationsCtrl.text = s.childrenCaseSheet.birthComplications;
    childMotherPregnancyCtrl.text = s.childrenCaseSheet.motherPregnancyHistory;
    childMotherMedicalCtrl.text = s.childrenCaseSheet.motherMedicalHistory;
    childFamilyHereditaryCtrl.text = s.childrenCaseSheet.familyHealthHereditary;
    childWalkingTeethingCtrl.text = s.childrenCaseSheet.walkingTeethingAge;
    childAbnormalBehaviorsCtrl.text = s.childrenCaseSheet.abnormalBehaviors;
    childFearsSpecificCtrl.text = s.childrenCaseSheet.childFears;
    childSleepingHabitsCtrl.text = s.childrenCaseSheet.childSleepingHabits;
    abnormalCravingsCtrl.text = s.childrenCaseSheet.abnormalCravings;
    childWormsCtrl.text = s.childrenCaseSheet.wormsProblems;
    childHeadCtrl.text = s.childrenCaseSheet.headSymptoms;
    childCoughAsthmaCtrl.text = s.childrenCaseSheet.coughAsthmaDetails;
    childStomachCtrl.text = s.childrenCaseSheet.stomachSymptoms;
    childStoolRectumCtrl.text = s.childrenCaseSheet.stoolRectumSymptoms;
    childSexualAwarenessCtrl.text = s.childrenCaseSheet.sexualAwareness;
    childAdditionalInfoCtrl.text = s.childrenCaseSheet.additionalChildInfo;
    endoDiagnosisCtrl.text = s.femaleEndocrine.medicalDiagnosis;
    endoHowStartedCtrl.text = s.femaleEndocrine.howAndWhenStarted;
    endoPhysioTriggerCtrl.text = s.femaleEndocrine.physiologicalCauseTrigger;
    endoEmotionalTriggerCtrl.text = s.femaleEndocrine.emotionalTriggers;
    endoManifestationLocCtrl.text = s.femaleEndocrine.diseaseManifestationLocation;
    endoOtherOrgansCtrl.text = s.femaleEndocrine.otherOrgansInvolved;
    endoGoitreCtrl.text = s.femaleEndocrine.goitreDetails;
    endoGlandsCtrl.text = s.femaleEndocrine.glandsProblems;
    endoSkinCtrl.text = s.femaleEndocrine.skinSymptoms;
    endoCardiacCtrl.text = s.femaleEndocrine.cardiacCirculatorySymptoms;
    endoStagesOfLifeCtrl.text = s.femaleEndocrine.stagesOfLife;
    endoMenstrualCtrl.text = s.femaleEndocrine.menstrualHistory;
    endoWeaknessCtrl.text = s.femaleEndocrine.physicalWeakness;
    endoRelationshipsCtrl.text = s.femaleEndocrine.relationshipDetails;
    acuteComplaintCtrl.text = s.acuteSheet.detailedComplaint;
    acuteCauseCtrl.text = s.acuteSheet.causeOfComplaint;
    acuteWorseCtrl.text = s.acuteSheet.whatMakesWorse;
    acuteBetterCtrl.text = s.acuteSheet.whatMakesBetter;
    acuteMentalConditionCtrl.text = s.acuteSheet.mentalConditionDuringSuffering;
    acuteWaterReqCtrl.text = s.acuteSheet.waterRequirement;
    acuteSweatCtrl.text = s.acuteSheet.sweatDetails;
    acutePostureCtrl.text = s.acuteSheet.postureModalities;
    acuteFeverCtrl.text = s.acuteSheet.acuteFeverDetails;
    acuteCoughCtrl.text = s.acuteSheet.coughRespirationDetail;
    acuteLooseDryCoughCtrl.text = s.acuteSheet.looseDryCoughDetails;
    acuteDiarrheaCtrl.text = s.acuteSheet.diarrheaConstipationDetails;
    acutePainCtrl.text = s.acuteSheet.bodyPainDetails;
    acuteUncommonSymptomsCtrl.text = s.acuteSheet.specialUncommonSymptoms;
    acuteAdditionalInfoCtrl.text = s.acuteSheet.additionalInfo;
    hungerTimeCtrl.text = s.generalSymptoms.hungerTime;
    hungerReactionCtrl.text = s.generalSymptoms.hungerReaction;
    eatingSpeedCtrl.text = s.generalSymptoms.eatingSpeed;
    thirstTimeCtrl.text = s.generalSymptoms.thirstTime;
    tasteChangesCtrl.text = s.generalSymptoms.tasteChanges;
    sleepPostureCtrl.text = s.dreamsSleep.sleepPosture;
    sleepRestrictionsCtrl.text = s.dreamsSleep.sleepPositionRestrictions;
    sleepBehaviorsCtrl.text = s.dreamsSleep.sleepBehaviors;
    childhoodDreamsCtrl.text = s.dreamsSleep.childhoodDreams;
  }

  HomeopathyChildhoodHistory buildChildhoodHistory(
      HomeopathyChildhoodHistory base) {
    return base.copyWith(
      childhoodNature: childhoodNatureCtrl.text.trim(),
      childhoodHabits: childhoodHabitsCtrl.text.trim(),
      childhoodFears: childhoodFearsCtrl.text.trim(),
      childhoodDreams: childhoodDreamsHistoryCtrl.text.trim(),
      childhoodRelationships: childhoodRelationshipsCtrl.text.trim(),
      childhoodSensitivities: childhoodSensitivitiesCtrl.text.trim(),
    );
  }

  HomeopathyChildrenCaseSheet buildChildrenCaseSheet(
      HomeopathyChildrenCaseSheet base) {
    final score = int.tryParse(childGraspingScoreCtrl.text.trim()) ?? 0;
    return base.copyWith(
      coldOrHeatSensitive: childColdHeatCtrl.text.trim(),
      behaviorWhenUpset: childBehaviorUpsetCtrl.text.trim(),
      whatMakesHappy: childWhatMakesHappyCtrl.text.trim(),
      schoolBehavior: childSchoolBehaviorCtrl.text.trim(),
      graspingIntelligenceScore: score,
      childTypeDescription: childTypeCtrl.text.trim(),
      vaccinationHistory: childVaccinationCtrl.text.trim(),
      favoriteSportActivity: childFavoriteSportCtrl.text.trim(),
      attitudeToParents: childAttitudeParentsCtrl.text.trim(),
      childMedicalHistory: childMedicalHistoryCtrl.text.trim(),
      maturityLevel: childMaturityCtrl.text.trim(),
      familyProblemsReaction: childFamilyProblemsCtrl.text.trim(),
      childIntrovertExtrovert: childIntrovertCtrl.text.trim(),
      independenceLevel: childIndependenceCtrl.text.trim(),
      dailyWaterIntake: childWaterIntakeCtrl.text.trim(),
      birthComplications: childBirthComplicationsCtrl.text.trim(),
      motherPregnancyHistory: childMotherPregnancyCtrl.text.trim(),
      motherMedicalHistory: childMotherMedicalCtrl.text.trim(),
      familyHealthHereditary: childFamilyHereditaryCtrl.text.trim(),
      walkingTeethingAge: childWalkingTeethingCtrl.text.trim(),
      abnormalBehaviors: childAbnormalBehaviorsCtrl.text.trim(),
      childFears: childFearsSpecificCtrl.text.trim(),
      childSleepingHabits: childSleepingHabitsCtrl.text.trim(),
      abnormalCravings: abnormalCravingsCtrl.text.trim(),
      wormsProblems: childWormsCtrl.text.trim(),
      headSymptoms: childHeadCtrl.text.trim(),
      coughAsthmaDetails: childCoughAsthmaCtrl.text.trim(),
      stomachSymptoms: childStomachCtrl.text.trim(),
      stoolRectumSymptoms: childStoolRectumCtrl.text.trim(),
      sexualAwareness: childSexualAwarenessCtrl.text.trim(),
      additionalChildInfo: childAdditionalInfoCtrl.text.trim(),
    );
  }

  HomeopathyFemaleEndocrine buildFemaleEndocrine(
      HomeopathyFemaleEndocrine base) {
    return base.copyWith(
      medicalDiagnosis: endoDiagnosisCtrl.text.trim(),
      howAndWhenStarted: endoHowStartedCtrl.text.trim(),
      physiologicalCauseTrigger: endoPhysioTriggerCtrl.text.trim(),
      emotionalTriggers: endoEmotionalTriggerCtrl.text.trim(),
      diseaseManifestationLocation: endoManifestationLocCtrl.text.trim(),
      otherOrgansInvolved: endoOtherOrgansCtrl.text.trim(),
      goitreDetails: endoGoitreCtrl.text.trim(),
      glandsProblems: endoGlandsCtrl.text.trim(),
      skinSymptoms: endoSkinCtrl.text.trim(),
      cardiacCirculatorySymptoms: endoCardiacCtrl.text.trim(),
      stagesOfLife: endoStagesOfLifeCtrl.text.trim(),
      menstrualHistory: endoMenstrualCtrl.text.trim(),
      physicalWeakness: endoWeaknessCtrl.text.trim(),
      relationshipDetails: endoRelationshipsCtrl.text.trim(),
    );
  }

  HomeopathyAcuteSheet buildAcuteSheet(HomeopathyAcuteSheet base) {
    return base.copyWith(
      detailedComplaint: acuteComplaintCtrl.text.trim(),
      causeOfComplaint: acuteCauseCtrl.text.trim(),
      whatMakesWorse: acuteWorseCtrl.text.trim(),
      whatMakesBetter: acuteBetterCtrl.text.trim(),
      mentalConditionDuringSuffering: acuteMentalConditionCtrl.text.trim(),
      waterRequirement: acuteWaterReqCtrl.text.trim(),
      sweatDetails: acuteSweatCtrl.text.trim(),
      postureModalities: acutePostureCtrl.text.trim(),
      acuteFeverDetails: acuteFeverCtrl.text.trim(),
      coughRespirationDetail: acuteCoughCtrl.text.trim(),
      looseDryCoughDetails: acuteLooseDryCoughCtrl.text.trim(),
      diarrheaConstipationDetails: acuteDiarrheaCtrl.text.trim(),
      bodyPainDetails: acutePainCtrl.text.trim(),
      specialUncommonSymptoms: acuteUncommonSymptomsCtrl.text.trim(),
      additionalInfo: acuteAdditionalInfoCtrl.text.trim(),
    );
  }

  HomeopathyGeneralSymptoms updateGeneralSymptoms(
      HomeopathyGeneralSymptoms base) {
    return base.copyWith(
      hungerTime: hungerTimeCtrl.text.trim(),
      hungerReaction: hungerReactionCtrl.text.trim(),
      eatingSpeed: eatingSpeedCtrl.text.trim(),
      thirstTime: thirstTimeCtrl.text.trim(),
      tasteChanges: tasteChangesCtrl.text.trim(),
    );
  }

  HomeopathyMentalEmotional updateMentalEmotional(
      HomeopathyMentalEmotional base) {
    return base.copyWith(
      upsetWorryTriggers: upsetWorryCtrl.text.trim(),
      fearDetails: fearDetailsCtrl.text.trim(),
      introvertExtrovert: introvertExtrovertCtrl.text.trim(),
      stressHistory: stressHistoryCtrl.text.trim(),
      stressCopingMethods: stressCopingCtrl.text.trim(),
      sensitivityDetails: sensitivityDetailsCtrl.text.trim(),
      fixedHabits: fixedHabitsCtrl.text.trim(),
      angerBodySymptoms: angerBodyCtrl.text.trim(),
      disorderSensitivity: disorderSensitivityCtrl.text.trim(),
      greatestGrief: greatestGriefCtrl.text.trim(),
      greatestJoys: greatestJoysCtrl.text.trim(),
      deeplyLikedActivities: deeplyLikedCtrl.text.trim(),
      deeplyDislikedMatters: deeplyDislikedCtrl.text.trim(),
      disagreeableMindAspects: disagreeableMindCtrl.text.trim(),
      lifeSituationPicture: lifeSituationCtrl.text.trim(),
    );
  }

  HomeopathyDreamsSleep updateDreamsSleep(HomeopathyDreamsSleep base) {
    return base.copyWith(
      sleepPosture: sleepPostureCtrl.text.trim(),
      sleepPositionRestrictions: sleepRestrictionsCtrl.text.trim(),
      sleepBehaviors: sleepBehaviorsCtrl.text.trim(),
      childhoodDreams: childhoodDreamsCtrl.text.trim(),
    );
  }

  void dispose() {
    childhoodNatureCtrl.dispose();
    childhoodHabitsCtrl.dispose();
    childhoodFearsCtrl.dispose();
    childhoodDreamsHistoryCtrl.dispose();
    childhoodRelationshipsCtrl.dispose();
    childhoodSensitivitiesCtrl.dispose();
    upsetWorryCtrl.dispose();
    fearDetailsCtrl.dispose();
    introvertExtrovertCtrl.dispose();
    stressHistoryCtrl.dispose();
    stressCopingCtrl.dispose();
    sensitivityDetailsCtrl.dispose();
    fixedHabitsCtrl.dispose();
    angerBodyCtrl.dispose();
    disorderSensitivityCtrl.dispose();
    greatestGriefCtrl.dispose();
    greatestJoysCtrl.dispose();
    deeplyLikedCtrl.dispose();
    deeplyDislikedCtrl.dispose();
    disagreeableMindCtrl.dispose();
    lifeSituationCtrl.dispose();
    childColdHeatCtrl.dispose();
    childBehaviorUpsetCtrl.dispose();
    childWhatMakesHappyCtrl.dispose();
    childSchoolBehaviorCtrl.dispose();
    childGraspingScoreCtrl.dispose();
    childTypeCtrl.dispose();
    childVaccinationCtrl.dispose();
    childFavoriteSportCtrl.dispose();
    childAttitudeParentsCtrl.dispose();
    childMedicalHistoryCtrl.dispose();
    childMaturityCtrl.dispose();
    childFamilyProblemsCtrl.dispose();
    childIntrovertCtrl.dispose();
    childIndependenceCtrl.dispose();
    childWaterIntakeCtrl.dispose();
    childBirthComplicationsCtrl.dispose();
    childMotherPregnancyCtrl.dispose();
    childMotherMedicalCtrl.dispose();
    childFamilyHereditaryCtrl.dispose();
    childWalkingTeethingCtrl.dispose();
    childAbnormalBehaviorsCtrl.dispose();
    childFearsSpecificCtrl.dispose();
    childSleepingHabitsCtrl.dispose();
    abnormalCravingsCtrl.dispose();
    childWormsCtrl.dispose();
    childHeadCtrl.dispose();
    childCoughAsthmaCtrl.dispose();
    childStomachCtrl.dispose();
    childStoolRectumCtrl.dispose();
    childSexualAwarenessCtrl.dispose();
    childAdditionalInfoCtrl.dispose();
    endoDiagnosisCtrl.dispose();
    endoHowStartedCtrl.dispose();
    endoPhysioTriggerCtrl.dispose();
    endoEmotionalTriggerCtrl.dispose();
    endoManifestationLocCtrl.dispose();
    endoOtherOrgansCtrl.dispose();
    endoGoitreCtrl.dispose();
    endoGlandsCtrl.dispose();
    endoSkinCtrl.dispose();
    endoCardiacCtrl.dispose();
    endoStagesOfLifeCtrl.dispose();
    endoMenstrualCtrl.dispose();
    endoWeaknessCtrl.dispose();
    endoRelationshipsCtrl.dispose();
    acuteComplaintCtrl.dispose();
    acuteCauseCtrl.dispose();
    acuteWorseCtrl.dispose();
    acuteBetterCtrl.dispose();
    acuteMentalConditionCtrl.dispose();
    acuteWaterReqCtrl.dispose();
    acuteSweatCtrl.dispose();
    acutePostureCtrl.dispose();
    acuteFeverCtrl.dispose();
    acuteCoughCtrl.dispose();
    acuteLooseDryCoughCtrl.dispose();
    acuteDiarrheaCtrl.dispose();
    acutePainCtrl.dispose();
    acuteUncommonSymptomsCtrl.dispose();
    acuteAdditionalInfoCtrl.dispose();
    hungerTimeCtrl.dispose();
    hungerReactionCtrl.dispose();
    eatingSpeedCtrl.dispose();
    thirstTimeCtrl.dispose();
    tasteChangesCtrl.dispose();
    sleepPostureCtrl.dispose();
    sleepRestrictionsCtrl.dispose();
    sleepBehaviorsCtrl.dispose();
    childhoodDreamsCtrl.dispose();
  }
}

