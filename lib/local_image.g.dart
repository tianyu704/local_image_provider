// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_image.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocalImage _$LocalImageFromJson(Map<String, dynamic> json) {
  return LocalImage(
    json['id'] as String,
    json['creationDate'] as num,
    json['pixelWidth'] as int,
    json['pixelHeight'] as int,
    json['lon'] as num,
    json['lat'] as num,
    json['path'] as String,
  );
}

Map<String, dynamic> _$LocalImageToJson(LocalImage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'pixelWidth': instance.pixelWidth,
      'pixelHeight': instance.pixelHeight,
      'creationDate': instance.creationDate,
      'lon': instance.lon,
      'lat': instance.lat,
      'path': instance.path,
    };
