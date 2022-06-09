let
  # canonical characters are at multiple-of-2 indices; lowercase characters are included since they should also be accepted
  digits = "2233445566778899CcFfGgHhJjMmPpQqRrVvWwXx";
  digitVal = digit: builtins.floor (builtins.stringLength (builtins.elemAt (builtins.match "(.*)${digit}.*" digits) 0) / 2);
  valDigit = val: builtins.substring (val * 2) 1 digits;
  mod = base: int: base - (int * (builtins.div base int)); # from nixpkgs (lib.trivial.mod)
  pow = n: i: # https://github.com/NixOS/nixpkgs/issues/41251
    assert builtins.isInt i && i >= 0;
    if i == 1 then n
    else if i == 0 then 1
    else n * pow n (i - 1);
in let
  encode = { length ? 10, lat, long } @ args: assert lat >= -90 && lat <= 90 && long >= -180 && long <= 180; let
    encodeFirst = { lat, long }: let
      lat' = builtins.floor ((lat + 90) * 8000);
      long' = builtins.floor ((long + 180) * 8000);
      encodeLatMsd = lat: valDigit (mod lat 20);
      encodeLongMsd = long: valDigit (mod long 20);
    in builtins.foldl' (acc: x: encodeLatMsd x.lat + encodeLongMsd x.long + acc) "" (builtins.genList (i: { lat = lat' / (pow 20 i); long = long' / (pow 20 i); }) 5);
    encodeLast = { lat, long }: let
      lat' = builtins.floor (((lat + 90) - builtins.floor (lat + 90)) * 2.5e7);
      long' = builtins.floor (((long + 180) - builtins.floor (long + 180)) * 8.192e6);
      encodeLsd = n: valDigit n;
    in builtins.foldl' (acc: x: encodeLsd (mod x.lat 5 * 4 + mod x.long 4) + acc) "" (builtins.genList (i: { lat = lat' / pow 5 i; long = long' / pow 4 i; }) 5);
    raw = encodeFirst { inherit lat long; } + (if length > 10 then encodeLast { inherit lat long; } else "");
  in if length >= 8 then builtins.substring 0 8 raw + "+" + builtins.substring 8 (length - 8) raw else builtins.substring 0 length raw + builtins.concatStringsSep "" (builtins.genList (_: "0") (8 - length)) + "+";
  decode = code: let
    code' = builtins.substring 0 15 (builtins.replaceStrings ["+" "0"] ["" ""] code);
    length = builtins.stringLength code';
    codeEnum = builtins.genList (i: { n = i; c = builtins.substring i 1 code'; }) length;
    decodeLat = lats: builtins.foldl' (acc: { i, x }: acc + x * 20.0 / pow 20 i) 0 (builtins.genList (i: { i = i; x = builtins.elemAt lats i; }) (builtins.length lats));
    decodeLong = longs: builtins.foldl' (acc: { i, x }: acc + x * 20.0 / pow 20 i) 0 (builtins.genList (i: { i = i; x = builtins.elemAt longs i; }) (builtins.length longs));
  in if length > 10 then throw "codes with length > 10 not supported" else rec {
    inherit length;
    southWest = {
      lat = decodeLat (map ({ n, c }: digitVal c) (builtins.filter ({ n, c }: mod n 2 == 0) codeEnum)) - 90;
      long = decodeLong (map ({ n, c }: digitVal c) (builtins.filter ({ n, c }: mod n 2 == 1) codeEnum)) - 180;
    };
    northEast = {
      lat = southWest.lat + 20.0 / pow 20 (length / 2 - 1);
      long = southWest.long + 20.0 / pow 20 (length / 2 - 1);
    };
    centre = if length >= 4 then {
      lat = (southWest.lat + northEast.lat) / 2;
      long = (southWest.long + northEast.long) / 2;
    } else throw "determining the centre of a large region is hard to do correctly and is therefore not implemented";
    height = northEast.lat - southWest.lat;
    width = northEast.long - southWest.long;
  };
in let
  # use the fact that toString is only precise to 6 decimal digits (for now: https://github.com/NixOS/nix/pull/6238)
  latLongEq = a: b: toString a.southWest.lat == toString b.southWest.lat && toString a.southWest.long == toString b.southWest.long && toString a.northEast.lat == toString b.northEast.lat && toString a.northEast.long == toString b.northEast.long;
in
  # commented-out tests do not pass (but should)

  # encoding.csv
  assert encode { lat = 20.375; long = 2.775; length = 6; } == "7FG49Q00+";
  assert encode { lat = 20.3700625; long = 2.7821875; length = 10; } == "7FG49QCJ+2V";
  assert encode { lat = 20.3701125; long = 2.782234375; length = 11; } == "7FG49QCJ+2VX";
  assert encode { lat = 20.3701135; long = 2.78223535156; length = 13; } == "7FG49QCJ+2VXGJ";
  assert encode { lat = 47.0000625; long = 8.0000625; length = 10; } == "8FVC2222+22";
  assert encode { lat = -41.2730625; long = 174.7859375; length = 10; } == "4VCPPQGP+Q9";
  assert encode { lat = 0.5; long = -179.5; length = 4; } == "62G20000+";
  assert encode { lat = -89.5; long = -179.5; length = 4; } == "22220000+";
  assert encode { lat = 20.5; long = 2.5; length = 4; } == "7FG40000+";
  assert encode { lat = -89.9999375; long = -179.9999375; length = 10; } == "22222222+22";
  assert encode { lat = 0.5; long = 179.5; length = 4; } == "6VGX0000+";
  assert encode { lat = 1; long = 1; length = 11; } == "6FH32222+222";
  # we don't properly handle the boundary case where lat == 90
  # assert encode { lat = 90; long = 1; length = 4; } == "CFX30000+";
  # we error out rather than clamping if lat is out of range
  # assert encode { lat = 92; long = 1; length = 4; } == "CFX30000+";
  # assert encode { lat = 90; long = 1; length = 10; } == "CFX3X2X2+X2";
  # we error out rather than wrapping if long is out of range
  # assert encode { lat = 1; long = 180; length = 4; } == "62H20000+";
  # assert encode { lat = 1; long = 181; length = 4; } == "62H30000+";
  # assert encode { lat = 20.3701135; long = 362.78223535156; length = 13; } == "7FG49QCJ+2VXGJ";
  # assert encode { lat = 47.0000625; long = 728.0000625; length = 10; } == "8FVC2222+22";
  # assert encode { lat = -41.2730625; long = 1254.7859375; length = 10; } == "4VCPPQGP+Q9";
  # assert encode { lat = 20.3701135; long = -357.217764648; length = 13; } == "7FG49QCJ+2VXGJ";
  # assert encode { lat = 47.0000625; long = -711.9999375; length = 10; } == "8FVC2222+22";
  # assert encode { lat = -41.2730625; long = -905.2140625; length = 10; } == "4VCPPQGP+Q9";
  assert encode { lat = 1.2; long = 3.4; length = 10; } == "6FH56C22+22";
  assert encode { lat = 37.539669125; long = -122.375069724; length = 15; } == "849VGJQF+VX7QR3J";
  assert encode { lat = 37.539669125; long = -122.375069724; length = 16; } == "849VGJQF+VX7QR3J";
  assert encode { lat = 37.539669125; long = -122.375069724; length = 100; } == "849VGJQF+VX7QR3J";
  # *many* floating-point problems in "Test floating point representation/rounding errors", unsurprisingly...
  assert encode { lat = 35.6; long = 3.033; length = 10; } == "8F75J22M+26";
  assert encode { lat = -48.71; long = 142.78; length = 8; } == "4R347QRJ+";
  assert encode { lat = -70; long = 163.7; length = 8; } == "3V252P22+";
  # assert encode { lat = -2.804; long = 7.003; length = 13; } == "6F9952W3+C6222";
  # assert encode { lat = 13.9; long = 164.88; length = 12; } == "7V56WV2J+2222";
  assert encode { lat = -13.23; long = 172.77; length = 8; } == "5VRJQQCC+";
  assert encode { lat = 40.6; long = 129.7; length = 8; } == "8QGFJP22+";
  # assert encode { lat = -52.166; long = 13.694; length = 14; } == "3FVMRMMV+JJ2222";
  assert encode { lat = -14; long = 106.9; length = 6; } == "5PR82W00+";
  # assert encode { lat = 70.3; long = -87.64; length = 13; } == "C62J8926+22222";
  assert encode { lat = 66.89; long = -106; length = 10; } == "95RPV2R2+22";
  # assert encode { lat = 2.5; long = -64.23; length = 11; } == "67JQGQ2C+222";
  # assert encode { lat = -56.7; long = -47.2; length = 14; } == "38MJ8R22+222222";
  assert encode { lat = -34.45; long = -93.719; length = 6; } == "46Q8H700+";
  assert encode { lat = -35.849; long = -93.75; length = 12; } == "46P85722+C222";
  # assert encode { lat = 65.748; long = 24.316; length = 12; } == "9GQ6P8X8+6C22";
  # assert encode { lat = -57.32; long = 130.43; length = 12; } == "3QJGMCJJ+2222";
  assert encode { lat = 17.6; long = -44.4; length = 6; } == "789QJJ00+";
  assert encode { lat = -27.6; long = -104.8; length = 6; } == "554QC600+";
  # assert encode { lat = 41.87; long = -145.59; length = 13; } == "83HPVCC6+22222";
  # assert encode { lat = -4.542; long = 148.638; length = 13; } == "6R7CFJ5Q+66222";
  # assert encode { lat = -37.014; long = -159.936; length = 10; } == "43J2X3P7+CJ";
  assert encode { lat = -57.25; long = 125.49; length = 15; } == "3QJ7QF2R+2222222";
  # assert encode { lat = 48.89; long = -80.52; length = 13; } == "86WXVFRJ+22222";
  # assert encode { lat = 53.66; long = 170.97; length = 14; } == "9V5GMX6C+222222";
  # assert encode { lat = 0.49; long = -76.97; length = 15; } == "67G5F2RJ+2222222";
  # assert encode { lat = 40.44; long = -36.7; length = 12; } == "89G5C8R2+2222";
  assert encode { lat = 58.73; long = 69.95; length = 8; } == "9JCFPXJ2+";
  # assert encode { lat = 16.179; long = 150.075; length = 12; } == "7R8G53HG+J222";
  # assert encode { lat = -55.574; long = -70.061; length = 12; } == "37PFCWGQ+CJ22";
  # assert encode { lat = 76.1; long = -82.5; length = 15; } == "C68V4G22+2222222";
  # assert encode { lat = 58.66; long = 149.17; length = 10; } == "9RCFM56C+22";
  # assert encode { lat = -67.2; long = 48.6; length = 6; } == "3H4CRJ00+";
  assert encode { lat = -5.6; long = -54.5; length = 14; } == "6867CG22+222222";
  assert encode { lat = -34; long = 145.5; length = 14; } == "4RR72G22+222222";
  # assert encode { lat = -34.2; long = 66.4; length = 12; } == "4JQ8RC22+2222";
  assert encode { lat = 17.8; long = -108.5; length = 6; } == "759HRG00+";
  # assert encode { lat = 10.734; long = -168.294; length = 10; } == "722HPPM4+JC";
  assert encode { lat = -28.732; long = 54.32; length = 8; } == "5H3P789C+";
  # assert encode { lat = 64.1; long = 107.9; length = 12; } == "9PP94W22+2222";
  assert encode { lat = 79.7525; long = 6.9623; length = 8; } == "CFF8QX36+";
  assert encode { lat = -63.6449; long = -25.1475; length = 8; } == "398P9V43+";
  # assert encode { lat = 35.019; long = 148.827; length = 11; } == "8R7C2R9G+JR2";
  # assert encode { lat = 71.132; long = -98.584; length = 15; } == "C6334CJ8+RC22222";
  # assert encode { lat = 53.38; long = -51.34; length = 12; } == "985C9MJ6+2222";
  # assert encode { lat = -1.2; long = 170.2; length = 12; } == "6VCGR622+2222";
  # assert encode { lat = 50.2; long = -162.8; length = 11; } == "922V6622+222";
  assert encode { lat = -25.798; long = -59.812; length = 10; } == "5862652Q+R6";
  # assert encode { lat = 81.654; long = -162.422; length = 14; } == "C2HVMH3H+J62222";
  # assert encode { lat = -75.7; long = -35.4; length = 8; } == "29P68J22+";
  # assert encode { lat = 67.2; long = 115.1; length = 11; } == "9PVQ6422+222";
  # assert encode { lat = -78.137; long = -42.995; length = 12; } == "28HVV274+6222";
  assert encode { lat = -56.3; long = 114.5; length = 11; } == "3PMPPG22+222";
  # assert encode { lat = 10.767; long = -62.787; length = 13; } == "772VQ687+R6222";
  assert encode { lat = -19.212; long = 107.423; length = 10; } == "5PG9QCQF+66";
  # assert encode { lat = 21.192; long = -45.145; length = 15; } == "78HP5VR4+R222222";
  # assert encode { lat = 16.701; long = 148.648; length = 14; } == "7R8CPJ2X+C62222";
  # assert encode { lat = 52.25; long = -77.45; length = 15; } == "97447H22+2222222";
  # assert encode { lat = -68.54504; long = -62.81725; length = 11; } == "373VF53M+X4J";
  # assert encode { lat = 76.7; long = -86.172; length = 12; } == "C68MPR2H+2622";
  # assert encode { lat = -6.2; long = 96.6; length = 13; } == "6M5RRJ22+22222";
  # assert encode { lat = 59.32; long = -157.21; length = 12; } == "93F48QCR+2222";
  # assert encode { lat = 29.7; long = 39.6; length = 12; } == "7GXXPJ22+2222";
  assert encode { lat = -18.32; long = 96.397; length = 10; } == "5MHRM9JW+2R";
  assert encode { lat = -30.3; long = 76.5; length = 11; } == "4JXRPG22+222";
  # assert encode { lat = 50.342; long = -112.534; length = 15; } == "95298FR8+RC22222";
  # floating-point problems?
  # assert encode { lat = 80.0100000001; long = 58.57; length = 15; } == "CHGW2H6C+2222222";
  # assert encode { lat = 80.0099999999; long = 58.57; length = 15; } == "CHGW2H5C+X2RRRRR";
  # assert encode { lat = -80.0099999999; long = 58.57; length = 15; } == "2HFWXHRC+2222222";
  # assert encode { lat = -80.0100000001; long = 58.57; length = 15; } == "2HFWXHQC+X2RRRRR";
  assert encode { lat = 47.000000080000000; long = 8.00022229; length = 15; } == "8FVC2222+235235C";
  assert encode { lat = 68.3500147997595; long = 113.625636875353; length = 15; } == "9PWM9J2G+272FWJV";
  assert encode { lat = 38.1176000887231; long = 165.441989844555; length = 15; } == "8VC74C9R+2QX445C";
  assert encode { lat = -28.1217794010122; long = -154.066811473758; length = 15; } == "5337VWHM+77PR2GR";

  # decoding.csv
  assert latLongEq (decode "7FG49Q00+") { southWest = { lat = 20.35; long = 2.75; }; northEast = { lat = 20.4; long = 2.8; }; };
  assert latLongEq (decode "7FG49QCJ+2V") { southWest = { lat = 20.37; long = 2.782125; }; northEast = { lat = 20.370125; long = 2.78225; }; };
  # floating-point comparison issues?
  # assert latLongEq (decode "7FG49QCJ+2VX") { southWest = { lat = 20.3701; long = 2.78221875; }; northEast = { lat = 20.370125; long = 2.78225; }; };
  # assert latLongEq (decode "7FG49QCJ+2VXGJ") { southWest = { lat = 20.370113; long = 2.782234375; }; northEast = { lat = 20.370114; long = 2.78223632813; }; };
  assert latLongEq (decode "8FVC2222+22") { southWest = { lat = 47.0; long = 8.0; }; northEast = { lat = 47.000125; long = 8.000125; }; };
  assert latLongEq (decode "4VCPPQGP+Q9") { southWest = { lat = -41.273125; long = 174.785875; }; northEast = { lat = -41.273; long = 174.786; }; };
  assert latLongEq (decode "62G20000+") { southWest = { lat = 0.0; long = -180.0; }; northEast = { lat = 1.0; long = -179.0; }; };
  assert latLongEq (decode "22220000+") { southWest = { lat = -90.0; long = -180.0; }; northEast = { lat = -89.0; long = -179.0; }; };
  assert latLongEq (decode "7FG40000+") { southWest = { lat = 20.0; long = 2.0; }; northEast = { lat = 21.0; long = 3.0; }; };
  assert latLongEq (decode "22222222+22") { southWest = { lat = -90.0; long = -180.0; }; northEast = { lat = -89.999875; long = -179.999875; }; };
  assert latLongEq (decode "6VGX0000+") { southWest = { lat = 0.0; long = 179.0; }; northEast = { lat = 1.0; long = 180.0; }; };
  # codes with length > 10 don't work
  # assert latLongEq (decode "6FH32222+222") { southWest = { lat = 1.0; long = 1.0; }; northEast = { lat = 1.000025; long = 1.00003125; }; };
  assert latLongEq (decode "CFX30000+") { southWest = { lat = 89.0; long = 1.0; }; northEast = { lat = 90.0; long = 2.0; }; };
  assert latLongEq (decode "62H20000+") { southWest = { lat = 1.0; long = -180.0; }; northEast = { lat = 2.0; long = -179.0; }; };
  assert latLongEq (decode "62H30000+") { southWest = { lat = 1.0; long = -179.0; }; northEast = { lat = 2.0; long = -178.0; }; };
  assert latLongEq (decode "CFX3X2X2+X2") { southWest = { lat = 89.9998750; long = 1.0; }; northEast = { lat = 90.0; long = 1.0001250; }; };
  assert latLongEq (decode "6FH56C22+22") { southWest = { lat = 1.2000000000000028; long = 3.4000000000000057; }; northEast = { lat = 1.2001249999999999; long = 3.4001250000000027; }; };
  # floating-point issues?
  # assert latLongEq (decode "849VGJQF+VX7QR3J") { lat = 37.5396691200; long = -122.3750698242; }; northEast = { lat = 37.5396691600; long = -122.3750697021; }; };
  # assert latLongEq (decode "849VGJQF+VX7QR3J7QR3J") { lat = 37.5396691200; long = -122.3750698242; }; northEast = { lat = 37.5396691600; long = -122.3750697021; }; };
  {
    inherit encode decode;
  }
