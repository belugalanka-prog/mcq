// A/L syllabus units, by subject. Each entry is [English name, Sinhala name].
// The English name is what gets stored on a question's `topic` column and
// passed to the start_topic_attempt() RPC — treat it as the stable id.
export const TOPICS = {
  physics: [
    ["Measurement", "මිනුම්"],
    ["Mechanics", "යන්ත්‍ර විද්‍යාව"],
    ["Oscillations and Waves", "දෝලන සහ තරංග"],
    ["Thermal Physics", "තාප භෞතික විද්‍යාව"],
    ["Gravitational Field", "ගුරුත්වාකර්ෂණ ක්ෂේත්‍ර"],
    ["Electrostatic Field (Electric Field)", "ස්ථිති විද්‍යුත් ක්ෂේත්‍ර"],
    ["Magnetic Field", "චුම්බක ක්ෂේත්‍ර"],
    ["Current Electricity", "ධාරා විද්‍යුතය"],
    ["Electronics", "ඉලෙක්ට්‍රොනික විද්‍යාව"],
    ["Mechanical Properties of Matter", "පදාර්ථයේ යාන්ත්‍රික ගුණ"],
    ["Matter and Radiation", "පදාර්ථ හා විකිරණ"],
  ],
  chemistry: [
    ["Atomic Structure", "පරමාණුක ව්‍යුහය"],
    ["Structure and Bonding", "ව්‍යුහය හා බන්ධන"],
    ["Chemical Calculations", "රසායනික ගණනය කිරීම්"],
    ["Gaseous State of Matter", "පදාර්ථයේ වායු අවස්ථාව"],
    ["Energetics (Thermodynamics)", "ශක්ති විද්‍යාව"],
    ["Chemistry of s, p, and d Block Elements", "s, p හා d ගොනු මූලද්‍රව්‍යවල රසායනය"],
    ["Basic Concepts of Organic Chemistry", "කාබනික රසායනයේ මූලික සංකල්ප"],
    ["Hydrocarbons and Halogenoalkanes", "හයිඩ්‍රෝකාබන හා හැලජන ඇල්කේන"],
    ["Oxygen-Containing Organic Compounds", "ඔක්සිජන් අඩංගු කාබනික සංයෝග"],
    ["Chemical Kinetics", "රසායනික චලිත විද්‍යාව"],
    ["Chemical Equilibrium", "රසායනික සමතුලිතතාව"],
    ["Electrochemistry", "විද්‍යුත් රසායනය"],
    ["Industrial Chemistry and Environmental Pollution", "කර්මාන්ත රසායනය හා පරිසර දූෂණය"],
    ["Organic Nitrogen Compounds", "කාබනික නයිට්‍රජන් සංයෝග"],
  ],
};
