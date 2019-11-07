import Flutter
import UIKit
import Photos

public enum LocalImageProviderMethods: String {
    case initialize
    case latest_images
    case image_bytes
    case images_in_album
    case albums
    case unknown // just for testing
    case latest_images_after_time //当前id 开始查 num条图片方法名
    case images_before_time       //⚠️查询结果都是按时间倒叙
    case images_after_time        //⚠️查询结果都是按时间倒叙
    case image_exists             //根据图片id 判断图片是否存在
}

public enum LocalImageProviderErrors: String {
    case imgLoadFailed
    case imgNotFound
    case missingOrInvalidArg
    case unimplemented
}

@available(iOS 10.0, *)
public class SwiftLocalImageProviderPlugin: NSObject, FlutterPlugin {
  let imageManager = PHImageManager.default()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "plugin.csdcorp.com/local_image_provider", binaryMessenger: registrar.messenger())
    let instance = SwiftLocalImageProviderPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case LocalImageProviderMethods.initialize.rawValue:
        initialize( result )
    case LocalImageProviderMethods.albums.rawValue:
        guard let albumType = call.arguments as? Int else {
            result(FlutterError( code: LocalImageProviderErrors.missingOrInvalidArg.rawValue,
                message:"Missing arg albumType",
                details: nil ))
            return
        }
        getAlbums( albumType, result)
    case LocalImageProviderMethods.latest_images_after_time.rawValue:
        guard let argsArr = call.arguments as? Dictionary<String,AnyObject>,
            let time = argsArr["time"] as? Int,
            let num = argsArr["num"] as? Int,
            let needLocation = argsArr["needLocation"] as? Int
            //
            else {
            result(FlutterError( code: LocalImageProviderErrors.missingOrInvalidArg.rawValue,
                message:"Missing arg maxPhotos",
                details: nil ))
            return
        }
        getTargetImages(_time: time, _num: num, _locationNum: needLocation, result);
    case LocalImageProviderMethods.images_after_time.rawValue:
        guard let argsArr = call.arguments as? Dictionary<String,AnyObject>,
                   let time = argsArr["time"] as? Int,
                   let needLocation = argsArr["needLocation"] as? Int
                   //
                   else {
                   result(FlutterError( code: LocalImageProviderErrors.missingOrInvalidArg.rawValue,
                       message:"Missing arg maxPhotos",
                       details: nil ))
                   return
               }
        getTimeBeforeOrAfterImages(_isAfter: true, _time: time, _locationNum: needLocation, result)
    case LocalImageProviderMethods.images_before_time.rawValue:
        guard let argsArr = call.arguments as? Dictionary<String,AnyObject>,
                   let time = argsArr["time"] as? Int,
                   let needLocation = argsArr["needLocation"] as? Int
                   //
                   else {
                   result(FlutterError( code: LocalImageProviderErrors.missingOrInvalidArg.rawValue,
                       message:"Missing arg maxPhotos",
                       details: nil ))
                   return
               }
        getTimeBeforeOrAfterImages(_isAfter: false, _time: time, _locationNum: needLocation, result)
    case LocalImageProviderMethods.latest_images.rawValue:
        guard let maxImages = call.arguments as? Int else {
            result(FlutterError( code: LocalImageProviderErrors.missingOrInvalidArg.rawValue,
                message:"Missing arg maxPhotos",
                details: nil ))
            return
        }
        getLatestImages( maxImages, result);
    case LocalImageProviderMethods.images_in_album.rawValue:
        guard let argsArr = call.arguments as? Dictionary<String,AnyObject>,
            let albumId = argsArr["albumId"] as? String,
            let maxImages = argsArr["maxImages"] as? Int
            else {
            result(FlutterError( code: LocalImageProviderErrors.missingOrInvalidArg.rawValue,
                message:"Missing arg maxPhotos",
                details: nil ))
            return
        }
        getImagesInAlbum( albumId: albumId, maxImages: maxImages, result);
    case LocalImageProviderMethods.image_bytes.rawValue:
        guard let argsArr = call.arguments as? Dictionary<String,AnyObject>,
            let localId = argsArr["id"] as? String,
            let width = argsArr["pixelWidth"] as? Int,
            let height = argsArr["pixelHeight"] as? Int
            else {
                result(FlutterError( code: LocalImageProviderErrors.missingOrInvalidArg.rawValue,
                    message:"Missing args requires id, pixelWidth, pixelHeight",
                    details: nil ))
                return
        }
        getPhotoImage( localId, width, height, result)
    case LocalImageProviderMethods.image_exists.rawValue:
        guard let localId = call.arguments as? String else {
            result(FlutterError( code: LocalImageProviderErrors.imgNotFound.rawValue,
                message:"img not found",
                details: nil ))
            return
        }
        getPhotoImageExist(localId, result)
    default:
        print("Unrecognized method: \(call.method)")
        result( FlutterMethodNotImplemented)
    }
  // result("iOS Photos min" )
  }
    
    private func initialize(_ result: @escaping FlutterResult) {
        if ( PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.notDetermined ) {
            PHPhotoLibrary.requestAuthorization({(status)->Void in
                result( status == PHAuthorizationStatus.authorized )
            });
        }
        else {
            result( true )
        }
    }
    
    private func getAlbums( _ albumType: Int, _ result: @escaping FlutterResult) {
        var albumEncodings = [String]();
        albumEncodings.append(contentsOf: getAlbumsWith( with: .album, subtype: .albumRegular ));
        albumEncodings.append(contentsOf: getAlbumsWith( with: .album, subtype: .albumSyncedEvent ));
        albumEncodings.append(contentsOf: getAlbumsWith( with: .album, subtype: .albumSyncedFaces));
        albumEncodings.append(contentsOf: getAlbumsWith( with: .album, subtype: .albumSyncedAlbum ));
        albumEncodings.append(contentsOf: getAlbumsWith( with: .album, subtype: .albumImported ));
        albumEncodings.append(contentsOf: getAlbumsWith( with: .album, subtype: .albumCloudShared ));

        result(albumEncodings)
    }
    
    private func getAlbumsWith( with: PHAssetCollectionType, subtype: PHAssetCollectionSubtype) -> [String] {
        let albums = PHAssetCollection.fetchAssetCollections(with: with, subtype: subtype, options: nil)
        var albumEncodings = [String]();
        albums.enumerateObjects{(object: AnyObject!,
        count: Int,
        stop: UnsafeMutablePointer<ObjCBool>) in
            if object is PHAssetCollection {
                let collection = object as! PHAssetCollection
                let imageOptions = PHFetchOptions()
                imageOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
                imageOptions.sortDescriptors = [NSSortDescriptor( key: "creationDate", ascending: false )]
                let containedImgs = PHAsset.fetchAssets(in: collection, options: imageOptions )
                var coverImgId = ""
                if let lastImg = containedImgs.firstObject {
                    coverImgId = lastImg.localIdentifier
                    var title = "n/a"
                    if let localizedTitle = collection.localizedTitle {
                        title = localizedTitle
                    }
                    let albumJson = """
                    {"id":"\(collection.localIdentifier)",
                    "title":"\(title)",
                    "coverImgId":"\(coverImgId)"}
                    """;
                    albumEncodings.append( albumJson )
                }
            }
        }
        return albumEncodings
    }
    private func getTimeBeforeOrAfterImages(_isAfter:Bool,_time: Int, _locationNum:Int, _ result: @escaping FlutterResult) {
      let date = SwiftLocalImageProviderPlugin.timeStampToDate(time: _time)
      let allPhotosOptions = PHFetchOptions()
      var p: NSPredicate?
        if (_time == 0) {
             p = NSPredicate(format: "mediaType = %d AND NOT ((mediaSubtype & %d) != 0)", PHAssetMediaType.image.rawValue,PHAssetMediaSubtype.photoScreenshot.rawValue)
        } else {
            if (_isAfter) {
                p = NSPredicate(format: "mediaType = %d AND NOT ((mediaSubtype & %d) != 0) AND creationDate > %@ ", PHAssetMediaType.image.rawValue,PHAssetMediaSubtype.photoScreenshot.rawValue,date as NSDate)
            } else {
                p = NSPredicate(format: "mediaType = %d AND NOT ((mediaSubtype & %d) != 0) AND creationDate < %@ ", PHAssetMediaType.image.rawValue,PHAssetMediaSubtype.photoScreenshot.rawValue,date as NSDate)
            }
        }
        allPhotosOptions.predicate = p
        allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]//降序
        let allPhotos = PHAsset.fetchAssets(with: allPhotosOptions)
        let photos = imagesToJson( allPhotos )
        result( photos )
    }
    //获取创建时间比最后一条time 大 的 num 条数据 （按时间倒序的所以比最后一条时间大 📷）
    private func getTargetImages( _time: Int,_num:Int,_locationNum:Int, _ result: @escaping FlutterResult) {
        
        let date = SwiftLocalImageProviderPlugin.timeStampToDate(time: _time)
        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.fetchLimit = _num
        var p: NSPredicate?
        
//        let location = CLLocation(latitude: 0, longitude: 0)
//        let locationPredicate = NSPredicate(format: "distanceToLocation:fromLocation:(%K,%@) < %f", "location", location as CLLocation, 1000)
        
        if (_time == 0) {
            p = NSPredicate(format: "mediaType = %d AND NOT ((mediaSubtype & %d) != 0)", PHAssetMediaType.image.rawValue,PHAssetMediaSubtype.photoScreenshot.rawValue)
            
        } else {
            p = NSPredicate(format: "mediaType = %d AND creationDate < %@ AND NOT ((mediaSubtype & %d) != 0)", PHAssetMediaType.image.rawValue,date as NSDate,PHAssetMediaSubtype.photoScreenshot.rawValue)
        }
        //[CKLocationSortDescriptor(key: "location", relativeLocation: location)] 按地点排序
        allPhotosOptions.predicate = p
        allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]//降序
        let allPhotos = PHAsset.fetchAssets(with: allPhotosOptions)
        let photos = imagesToJson( allPhotos )
        result( photos )
    }
    
    private func getLatestImages( _ maxPhotos: Int, _ result: @escaping FlutterResult) {
        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.fetchLimit = maxPhotos
        allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotos = PHAsset.fetchAssets(with: allPhotosOptions)
        let photos = imagesToJson( allPhotos )
        result( photos )
    }

    private func imagesToJson( _ images: PHFetchResult<PHAsset> ) -> [String] {
        var photosJson = [String]()
        let df = ISO8601DateFormatter()
        images.enumerateObjects{(object: AnyObject!,
            count: Int,
            stop: UnsafeMutablePointer<ObjCBool>) in
            
            
            
            
            if object is PHAsset{
                let asset = object as! PHAsset
                
    
                let creationDate = df.string(from: asset.creationDate!);
                let createDateInt = SwiftLocalImageProviderPlugin.stringToTimeStamp(stringTime: creationDate)
                let assetJson = """
                {"id":"\(asset.localIdentifier)",
                "creationDate":\(createDateInt),
                "lat":\(asset.location?.coordinate.latitude ?? 0),
                "lon":\(asset.location?.coordinate.longitude ?? 0),
                "pixelWidth":\(asset.pixelWidth),
                "pixelHeight":\(asset.pixelHeight)}
                """;
                 
                photosJson.append( assetJson )
            }
        }
        return photosJson
    }
    
    private func getImagesInAlbum( albumId: String, maxImages: Int, _ result: @escaping FlutterResult) {
        var photos = [String]()
        let albumOptions = PHFetchOptions()
        let albumResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: albumOptions )
        guard albumResult.count > 0 else {
            result( photos )
            return
        }
        if let album = albumResult.firstObject {
            let allPhotosOptions = PHFetchOptions()
            allPhotosOptions.fetchLimit = maxImages
            allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let albumPhotos = PHAsset.fetchAssets(in: album, options: allPhotosOptions)
            photos = imagesToJson( albumPhotos )
        }
       result( photos )
    }

    private func getPhotoImageExist(_ id: String,_ flutterResult: @escaping FlutterResult) {
        let fetchOptions = PHFetchOptions()
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: fetchOptions )
        flutterResult(1 == fetchResult.count)
    }
    private func getPhotoImage(_ id: String, _ pixelHeight: Int, _ pixelWidth: Int, _ flutterResult: @escaping FlutterResult) {
        let fetchOptions = PHFetchOptions()
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: fetchOptions )
        if ( 1 == fetchResult.count ) {
            let asset = fetchResult.firstObject!
            let targetSize = CGSize( width: pixelWidth, height: pixelHeight )
            let contentMode = PHImageContentMode.aspectFit
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = false
            requestOptions.isNetworkAccessAllowed = true
            imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: requestOptions, resultHandler: {(result, info)->Void in
                if let resultInfo = info
                {
                    let degraded = resultInfo[PHImageResultIsDegradedKey] as? Bool
                    if ( degraded ?? false ) {
                        return
                    }
                }
                if let image = result {
        
                    let nsdata = SwiftLocalImageProviderPlugin.resetSizeOfImageData(sourceImage: image, maxSize: 30)
                    let data = Data(referencing: nsdata)
                    //let data =UIImageJPEGRepresentation(image, 0.7 );
                    let typedData = FlutterStandardTypedData( bytes: data );
                    DispatchQueue.main.async {
                        flutterResult( typedData)
                    }
                }
                else {
                    print("Could not load")
                    DispatchQueue.main.async {
                        flutterResult(FlutterError( code: LocalImageProviderErrors.imgLoadFailed.rawValue, message: "Could not load image: \(id)", details: nil ))
                    }
                }
            });
        }
        else {
            DispatchQueue.main.async {
                flutterResult(FlutterError( code: LocalImageProviderErrors.imgNotFound.rawValue, message:"Image not found: \(id)", details: nil ))
            }
        }
    }
    
    //系统时间转毫秒时间戳
    static func stringToTimeStamp(stringTime:String)->Int {

        let df = ISO8601DateFormatter()
        let dateString = stringTime //df.string(from: Date()) // "2018-01-23T03:06:46.232Z"
        let date = df.date(from: dateString)     // "2018-01-23 03:06:46 +0000\n"
            
        let dateStamp:TimeInterval = date!.timeIntervalSince1970 * 1000
        let dateSt:Int = Int(dateStamp)
        return dateSt
    }
    
    static func timeStampToDate(time:Int)->Date {
        if (time == 0) {return Date()}
//        let df = ISO8601DateFormatter()
//        let dateString = String(time/1000)
//        let date = df.date(from: dateString)
        let date = Date(timeIntervalSince1970:TimeInterval(time/1000))
        return date// "2018-01-23T03:06:46.232Z"
    }
    
    
    
    ///压缩image到目标KB  maxSize:
  static  func resetSizeOfImageData(sourceImage: UIImage!, maxSize: Int) -> NSData {
        
        //先判断当前质量是否满足要求，不满足再进行压缩
        var finallImageData = UIImageJPEGRepresentation(sourceImage,1.0)
        let sizeOrigin      = finallImageData?.count
        let sizeOriginKB    = sizeOrigin! / 1024
        if sizeOriginKB <= maxSize {
            return finallImageData! as NSData
        }
        
        //获取原图片宽高比
        let sourceImageAspectRatio = sourceImage.size.width/sourceImage.size.height
        //先调整分辨率
        var defaultSize = CGSize(width: 1024, height: 1024/sourceImageAspectRatio)
        let newImage =  newSizeImage(size: defaultSize, sourceImage: sourceImage)
        
        finallImageData = UIImageJPEGRepresentation(newImage,1.0);
        
        //保存压缩系数
        let compressionQualityArr = NSMutableArray()
        let avg = CGFloat(1.0/250)
        var value = avg
        
        var i = 250
        repeat {
            i -= 1
            value = CGFloat(i)*avg
            compressionQualityArr.add(value)
        } while i >= 1
        
        /*
         调整大小
         说明：压缩系数数组compressionQualityArr是从大到小存储。
         */
        //思路：使用二分法搜索
        finallImageData = halfFuntion(arr: compressionQualityArr.copy() as! [CGFloat], image: newImage, sourceData: finallImageData!, maxSize: maxSize)
        //如果还是未能压缩到指定大小，则进行降分辨率
        while finallImageData?.count == 0 {
            //每次降100分辨率
            let reduceWidth = 100.0
            let reduceHeight = 100.0/sourceImageAspectRatio
            if (defaultSize.width-CGFloat(reduceWidth)) <= 0 || (defaultSize.height-CGFloat(reduceHeight)) <= 0 {
                break
            }
            defaultSize = CGSize(width: (defaultSize.width-CGFloat(reduceWidth)), height: (defaultSize.height-CGFloat(reduceHeight)))
            let image = self.newSizeImage(size: defaultSize, sourceImage: UIImage.init(data: UIImageJPEGRepresentation(newImage, compressionQualityArr.lastObject as! CGFloat)!)!)
            finallImageData = self.halfFuntion(arr: compressionQualityArr.copy() as! [CGFloat], image: image, sourceData: UIImageJPEGRepresentation(image,1.0)!, maxSize: maxSize)
        }
        
        return finallImageData! as NSData
    }
    
    // MARK: - 调整图片分辨率/尺寸（等比例缩放）
  static  func newSizeImage(size: CGSize, sourceImage: UIImage) -> UIImage {
        var newSize = CGSize(width: sourceImage.size.width, height: sourceImage.size.height)
        let tempHeight = newSize.height / size.height
        let tempWidth = newSize.width / size.width
        
        if tempWidth > 1.0 && tempWidth > tempHeight {
            newSize = CGSize(width: sourceImage.size.width / tempWidth, height: sourceImage.size.height / tempWidth)
        } else if tempHeight > 1.0 && tempWidth < tempHeight {
            newSize = CGSize(width: sourceImage.size.width / tempHeight, height: sourceImage.size.height / tempHeight)
        }
        
        UIGraphicsBeginImageContext(newSize)
        sourceImage.draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
    }
    
    // MARK: - 二分法
  static  func halfFuntion(arr: [CGFloat], image: UIImage, sourceData finallImageData: Data, maxSize: Int) -> Data? {
        var tempFinallImageData = finallImageData
        
        var tempData = Data.init()
        var start = 0
        var end = arr.count - 1
        var index = 0
        
        var difference = Int.max
        while start <= end {
            index = start + (end - start)/2
            
            tempFinallImageData = UIImageJPEGRepresentation(image, arr[index])!
            
            let sizeOrigin = tempFinallImageData.count
            let sizeOriginKB = sizeOrigin / 1024
            
            print("当前降到的质量：\(sizeOriginKB)\n\(index)----\(arr[index])")
            
            if sizeOriginKB > maxSize {
                start = index + 1
            } else if sizeOriginKB < maxSize {
                if maxSize-sizeOriginKB < difference {
                    difference = maxSize-sizeOriginKB
                    tempData = tempFinallImageData
                }
                if index<=0 {
                    break
                }
                end = index - 1
            } else {
                break
            }
        }
        return tempData
    }
    
}
