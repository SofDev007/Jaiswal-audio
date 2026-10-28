import 'package:Bloomee/screens/widgets/round_carousel.dart';

/// The photos on the About page's Round carousel, front one first.
///
/// Photos live in `assets/images/about/` (700x770, no metadata; made from the
/// originals in `D:\VSC Practise\jarx-photos`). Everything here is public:
/// anyone can unpack it from the APK, and it is in the public GitHub repo.
const aboutPhotos = <AboutPhoto>[
  AboutPhoto(asset: 'assets/images/about/1.jpg', caption: "hi, I'm Arnav"),
  AboutPhoto(
      asset: 'assets/images/about/2.jpg', caption: 'somewhere quiet, music on'),
  AboutPhoto(asset: 'assets/images/about/3.jpg', caption: 'quiet mode: on'),
  AboutPhoto(
      asset: 'assets/images/about/4.jpg', caption: 'looking for the next song'),
  AboutPhoto(
      asset: 'assets/images/about/5.jpg',
      caption: 'neon lights, loud playlist'),
  AboutPhoto(
      asset: 'assets/images/about/6.jpg', caption: 'my first beta-tester'),
];
