# open-location-code.nix

a Nix implementation of the [Open Location Code](https://github.com/google/open-location-code) specification

## Notes

This library is not strictly compliant with the specification.
In particular, be aware of the following:

- only `encode` and `decode` are provided; the validation methods, as well as all methods involving short codes, are absent
- latitudes and longitudes outside the normal range will be rejected by `encode`, not clamped or wrapped
- `decode` cannot decode plus codes with length greater than 10 (i.e. codes with more than 2 digits after the plus)
- most of the boundary cases (e.g. a latitude of 90°) are not handled correctly
- floating-point errors abound (see the included tests for details)

## Usage

This is a Nix flake; add it to your `flake.nix` like any other flake.

The `lib` output contains two functions, `encode` and `decode`.

To generate a plus code from latitude and longitude, pass `lat` and `long` to `lib.encode`.
You may optionally also pass a `length`; if you don’t, a code of length 10 will be generated.

To calculate coordinates from a plus code, pass the code to `lib.decode`.
The result will be an attrset with `southWest` and `northEast` attributes, which form the bounding box of the region,
as well as a `height` and `width` in degrees based on the precision of the code (see also the `length` attribute of the result).
The `centre` attribute will only be available if the region described is sufficiently small,
since simply taking the mean of two opposing corners of the region may not necessarily accurately represent the true centre of the region.
All three positions are an attrset containing a `lat` and a `long`.

## Reuse

Do whatever you like, just don’t blame me if it breaks.

## Contributions

Please, do something more productive than submitting patches to this library.
