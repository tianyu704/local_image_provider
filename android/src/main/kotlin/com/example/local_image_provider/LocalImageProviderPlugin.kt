package com.example.local_image_provider

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.ContentResolver
import android.content.pm.PackageManager
import android.os.Build
import android.graphics.Bitmap
import android.net.Uri
import android.nfc.Tag
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.PluginRegistry.Registrar
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import kotlin.collections.ArrayList


enum class LocalImageProviderErrors {
    imgLoadFailed,
    imgNotFound,
    missingOrInvalidArg,
    multipleRequests,
    unimplemented
}

class LocalImageProviderPlugin(activity: Activity) : MethodCallHandler,
        PluginRegistry.RequestPermissionsResultListener {
    val pluginActivity: Activity = activity
    private val application: Application = activity.application
    private val isoFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SZZZZZ")
    private val minSdkForImageSupport = 8
    private val imagePermissionCode = 34264
    private var activeResult: Result? = null
    private var initializedSuccessfully: Boolean = false
    private var permissionGranted: Boolean = false
    private val imageColums = arrayOf(MediaStore.Images.ImageColumns.DISPLAY_NAME,
            MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME,
            MediaStore.Images.ImageColumns.DATE_TAKEN,
            MediaStore.Images.ImageColumns.TITLE,
            MediaStore.Images.ImageColumns.HEIGHT,
            MediaStore.Images.ImageColumns.WIDTH,
            MediaStore.Images.ImageColumns.LONGITUDE,
            MediaStore.Images.ImageColumns.LATITUDE,
            MediaStore.Images.ImageColumns.DATA,
            MediaStore.MediaColumns._ID)

    companion object {
        @JvmStatic
        fun registerWith(registrar: Registrar) {
            val channel = MethodChannel(registrar.messenger(), "plugin.csdcorp.com/local_image_provider")
            val imagePlugin = LocalImageProviderPlugin(registrar.activity())
            registrar.addRequestPermissionsResultListener(imagePlugin)
            channel.setMethodCallHandler(imagePlugin)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> initialize(result)
            "latest_images" -> {
                if (null != call.arguments && call.arguments is Int) {
                    val maxResults = call.arguments as Int
                    getLatestImages(maxResults, result)
                } else {
                    result.error(LocalImageProviderErrors.missingOrInvalidArg.name,
                            "Missing arg maxPhotos", null)
                }
            }
            "latest_images_after_time" -> {
                var time = call.argument<Any>("time")
                val num = call.argument<Int>("num")
                val needLocation = call.argument<Int>("needLocation")
                if (time is Int) {
                    time = time.toLong()
                }
                getLatestImagesAfterTime(time as Long, num as Int, needLocation as Int, result)
            }

            "images_after_time" -> {
                var time = call.argument<Any>("time")
                val needLocation = call.argument<Int>("needLocation")
                if (time is Int) {
                    time = time.toLong()
                }
                getImagesAfterTime(time as Long, needLocation as Int, result)
            }

            "images_before_time" -> {
                var time = call.argument<Any>("time")
                val needLocation = call.argument<Int>("needLocation")
                if (time is Int) {
                    time = time.toLong()
                }
                getImagesBeforeTime(time as Long, needLocation as Int, result)
            }

            "albums" -> {
                if (null != call.arguments && call.arguments is Int) {
                    val localAlbumType = call.arguments as Int
                    getAlbums(localAlbumType, result)
                } else {
                    result.error(LocalImageProviderErrors.missingOrInvalidArg.name,
                            "Missing arg albumType", null)
                }
            }
            "image_bytes" -> {
                val path = call.argument<String>("id")
                val width = call.argument<Int>("pixelWidth")
                val height = call.argument<Int>("pixelHeight")
                if (path != null && width != null && height != null) {
                    getImageBytes(path, width, height, result)
                } else {
                    result.error(LocalImageProviderErrors.missingOrInvalidArg.name,
                            "Missing arg requires id, width, height", null)
                }
            }
            "images_in_album" -> {
                val albumId = call.argument<String>("albumId")
                val maxImages = call.argument<Int>("maxImages")
                if (albumId != null && maxImages != null) {
                    findImagesInAlbum(albumId, maxImages, result)
                } else {
                    result.error(LocalImageProviderErrors.missingOrInvalidArg.name,
                            "Missing arg requires albumId, maxImages", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: Result) {
        if (sdkVersionTooLow(result)) {
            return
        }
        if (null != activeResult) {
            result.error(LocalImageProviderErrors.multipleRequests.name,
                    "Only one initialize at a time", null)
            return
        }
        activeResult = result
        initializeIfPermitted(application)
    }

    private fun sdkVersionTooLow(result: Result): Boolean {
        if (Build.VERSION.SDK_INT < minSdkForImageSupport) {
            result.success(false)
            return true
        }
        return false
    }

    private fun isNotInitialized(result: Result): Boolean {
        if (!initializedSuccessfully) {
            result.success(false)
        }
        return !initializedSuccessfully
    }


    private fun getAlbums(localAlbumType: Int, result: Result) {
        if (isNotInitialized(result)) {
            return
        }
        val albums = ArrayList<String>()
        Thread(Runnable {
            albums.addAll(getAlbumsFromLocation(MediaStore.Images.Media.INTERNAL_CONTENT_URI))
            albums.addAll(getAlbumsFromLocation(MediaStore.Images.Media.EXTERNAL_CONTENT_URI))
            pluginActivity.runOnUiThread { result.success(albums) }
        }).start()

    }

    private fun getAlbumsFromLocation(imgUri: Uri): ArrayList<String> {
        val mediaColumns = arrayOf(
                "DISTINCT " + MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME,
                MediaStore.Images.ImageColumns.BUCKET_ID
        )
        val sortOrder = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} ASC"
        val mediaResolver = pluginActivity.contentResolver
        val albums = ArrayList<String>()
        val imageCursor = mediaResolver.query(imgUri, mediaColumns, null,
                null, sortOrder)
        imageCursor?.use {
            val titleColumn = imageCursor.getColumnIndexOrThrow(
                    MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME)
            val idColumn = imageCursor.getColumnIndexOrThrow(
                    MediaStore.Images.ImageColumns.BUCKET_ID)
            while (imageCursor.moveToNext()) {
                val bucketId = imageCursor.getString(idColumn)
                val coverImgId = getAlbumsCoverImage(bucketId, imgUri)
                val imgJson = JSONObject()
                imgJson.put("title", imageCursor.getString(titleColumn))
                imgJson.put("id", bucketId)
                imgJson.put("coverImgId", coverImgId)
                albums.add(imgJson.toString())
            }
        }
        return albums
    }

    private fun getAlbumsCoverImage(bucketId: String, imgUri: Uri): String {
        var coverImgId = String()
        val mediaColumns = arrayOf(
                MediaStore.Images.ImageColumns._ID,
                MediaStore.Images.ImageColumns.BUCKET_ID,
                MediaStore.Images.ImageColumns.DATE_TAKEN
        )
        val sortOrder = "${MediaStore.Images.ImageColumns.DATE_TAKEN} DESC LIMIT 1"
        val selection = "${MediaStore.Images.ImageColumns.BUCKET_ID} = ?"
        val selectionArgs = arrayOf(bucketId)
        val mediaResolver = pluginActivity.contentResolver
        val imageCursor = mediaResolver.query(imgUri, mediaColumns, selection,
                selectionArgs, sortOrder)
        imageCursor?.use {
            val idColumn = imageCursor.getColumnIndexOrThrow(MediaStore.Images.ImageColumns._ID)
            while (imageCursor.moveToNext()) {
                coverImgId = imageCursor.getString(idColumn)
            }
        }
        return coverImgId
    }

    private fun getLatestImages(maxResults: Int, result: Result) {
        if (isNotInitialized(result)) {
            return
        }
        Thread(Runnable {
            val imgUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val sortOrder = "${MediaStore.Images.ImageColumns.DATE_TAKEN} DESC LIMIT $maxResults"
            val mediaResolver = pluginActivity.contentResolver
            val images = findImagesToJson(mediaResolver, imgUri, null, null, sortOrder)
            pluginActivity.runOnUiThread { result.success(images) }
        }).start()
    }

    private fun getLatestImagesAfterTime(time: Long, num: Int, needLocation: Int, result: Result) {
        if (isNotInitialized(result)) {
            return
        }
//        var albumId = findCameraAlbumId()
        Thread(Runnable {
            val imgUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val sortOrder = "${MediaStore.Images.ImageColumns.DATE_TAKEN} DESC LIMIT $num"
            var selection: String? = null
            var selectionArgs: Array<String>? = null
            if (time != 0L) {
                if (needLocation == 1) {
                    selection = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} = 'Camera' AND ${MediaStore.Images.ImageColumns.DATE_TAKEN} < ? AND ${MediaStore.Images.ImageColumns.LONGITUDE} != 0 AND ${MediaStore.Images.ImageColumns.LATITUDE} != 0"
                } else {
                    selection = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} = 'Camera' AND ${MediaStore.Images.ImageColumns.DATE_TAKEN} < ?"
                }
                selectionArgs = arrayOf("$time")
            } else {
                if (needLocation == 1) {
                    selection = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} = 'Camera' AND ${MediaStore.Images.ImageColumns.LONGITUDE} != 0 AND ${MediaStore.Images.ImageColumns.LATITUDE} != 0"
                }
            }
            val mediaResolver = pluginActivity.contentResolver
            val images = findImagesToJson(mediaResolver, imgUri, selection, selectionArgs, sortOrder)
            pluginActivity.runOnUiThread { result.success(images) }
        }).start()
    }

    private fun getImagesAfterTime(time: Long, needLocation: Int, result: Result) {
        if (isNotInitialized(result)) {
            return
        }
//        var albumId = findCameraAlbumId()
        Thread(Runnable {
            val imgUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val sortOrder = "${MediaStore.Images.ImageColumns.DATE_TAKEN} DESC"
            var selection: String? = null
            var selectionArgs: Array<String>? = null
            if (time != 0L) {
                if (needLocation == 1) {
                    selection = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} = 'Camera' AND ${MediaStore.Images.ImageColumns.DATE_TAKEN} < ? AND ${MediaStore.Images.ImageColumns.LONGITUDE} != 0 AND ${MediaStore.Images.ImageColumns.LATITUDE} != 0"
                } else {
                    selection = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} = 'Camera' AND ${MediaStore.Images.ImageColumns.DATE_TAKEN} < ?"
                }
                selectionArgs = arrayOf("$time")
            } else {
                if (needLocation == 1) {
                    selection = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} = 'Camera' AND ${MediaStore.Images.ImageColumns.LONGITUDE} != 0 AND ${MediaStore.Images.ImageColumns.LATITUDE} != 0"
                }
            }
            val mediaResolver = pluginActivity.contentResolver
            val images = findImagesToJson(mediaResolver, imgUri, selection, selectionArgs, sortOrder)
            pluginActivity.runOnUiThread { result.success(images) }
        }).start()
    }

    private fun getImagesBeforeTime(time: Long, needLocation: Int, result: Result) {
        if (isNotInitialized(result)) {
            return
        }
//        var albumId = findCameraAlbumId()
        Thread(Runnable {
            val imgUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val sortOrder = "${MediaStore.Images.ImageColumns.DATE_TAKEN} DESC"
            var selection: String? = null
            var selectionArgs: Array<String>? = null
            if (time != 0L) {
                if (needLocation == 1) {
                    selection = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} = 'Camera' AND ${MediaStore.Images.ImageColumns.DATE_TAKEN} > ? AND ${MediaStore.Images.ImageColumns.LONGITUDE} != 0 AND ${MediaStore.Images.ImageColumns.LATITUDE} != 0"
                } else {
                    selection = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} = 'Camera' AND ${MediaStore.Images.ImageColumns.DATE_TAKEN} > ?"
                }
                selectionArgs = arrayOf("$time")
            } else {
                if (needLocation == 1) {
                    selection = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} = 'Camera' AND ${MediaStore.Images.ImageColumns.LONGITUDE} != 0 AND ${MediaStore.Images.ImageColumns.LATITUDE} != 0"
                }
            }
            val mediaResolver = pluginActivity.contentResolver
            val images = findImagesToJson(mediaResolver, imgUri, selection, selectionArgs, sortOrder)
            pluginActivity.runOnUiThread { result.success(images) }
        }).start()
    }

    private fun findCameraAlbumId(): String {
        val mediaColumns = arrayOf(
                "DISTINCT " + MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME,
                MediaStore.Images.ImageColumns.BUCKET_ID
        )
        val mediaResolver = pluginActivity.contentResolver
        val selection = "${MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME} = 'Camera'"
        var albumId = ""

        val imageCursor = mediaResolver.query(MediaStore.Images.Media.INTERNAL_CONTENT_URI, mediaColumns, selection,
                null, null)
        imageCursor?.use {
            val idColumn = imageCursor.getColumnIndexOrThrow(
                    MediaStore.Images.ImageColumns.BUCKET_ID)
            while (imageCursor.moveToNext()) {
                albumId = imageCursor.getString(idColumn)
                Log.e("albumId", albumId)
                return albumId
            }
        }
        if (albumId == "") {
            val imageCursor = mediaResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, mediaColumns, selection,
                    null, null)
            imageCursor?.use {
                val idColumn = imageCursor.getColumnIndexOrThrow(
                        MediaStore.Images.ImageColumns.BUCKET_ID)
                while (imageCursor.moveToNext()) {
                    albumId = imageCursor.getString(idColumn)
                    Log.e("albumId", albumId)
                    return albumId
                }
            }
        }
        return albumId
    }

    private fun findImagesInAlbum(albumId: String, maxImages: Int, result: Result) {
        if (isNotInitialized(result)) {
            return
        }
        Thread(Runnable {
            val imgUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val sortOrder = "${MediaStore.Images.ImageColumns.DATE_TAKEN} DESC LIMIT $maxImages"
            val selection = "${MediaStore.Images.ImageColumns.BUCKET_ID} = ?"
            val selectionArgs = arrayOf(albumId)
            val mediaResolver = pluginActivity.contentResolver
            val images = findImagesToJson(mediaResolver, imgUri, selection, selectionArgs, sortOrder)
            pluginActivity.runOnUiThread { result.success(images) }
        }).start()
    }

    private fun findImagesToJson(mediaResolver: ContentResolver, imgUri: Uri, selection: String?,
                                 selectionArgs: Array<String>?, sortOrder: String?):
            ArrayList<String> {
        val images = ArrayList<String>()
        val imageCursor = mediaResolver.query(imgUri, imageColums, selection,
                selectionArgs, sortOrder)
        imageCursor?.use {
            val widthColumn = imageCursor.getColumnIndexOrThrow(MediaStore.Images.ImageColumns.WIDTH)
            val heightColumn = imageCursor.getColumnIndexOrThrow(MediaStore.Images.ImageColumns.HEIGHT)
            val dateColumn = imageCursor.getColumnIndexOrThrow(MediaStore.Images.ImageColumns.DATE_TAKEN)
            val titleColumn = imageCursor.getColumnIndexOrThrow(MediaStore.Images.ImageColumns.TITLE)
            val idColumn = imageCursor.getColumnIndexOrThrow(MediaStore.Images.ImageColumns._ID)
            val lon = imageCursor.getColumnIndexOrThrow(MediaStore.Images.Media.LONGITUDE)
            val lat = imageCursor.getColumnIndexOrThrow(MediaStore.Images.ImageColumns.LATITUDE)
            val path = imageCursor.getColumnIndexOrThrow(MediaStore.Images.ImageColumns.DATA)
            while (imageCursor.moveToNext()) {
                val imgJson = JSONObject()
                imgJson.put("title", imageCursor.getString(titleColumn))
                imgJson.put("pixelWidth", imageCursor.getInt(widthColumn))
                imgJson.put("pixelHeight", imageCursor.getInt(heightColumn))
                imgJson.put("id", imageCursor.getString(idColumn))
                imgJson.put("creationDate", imageCursor.getLong(dateColumn))
                imgJson.put("lon", imageCursor.getDouble(lon))
                imgJson.put("lat", imageCursor.getDouble(lat))
                imgJson.put("path", imageCursor.getString(path))
                images.add(imgJson.toString())
            }
        }
        return images
    }

    private fun getImageBytes(path: String, width: Int, height: Int, result: Result) {
        if (isNotInitialized(result)) {
            return
        }
        Thread(Runnable {
//            val imgUri = Uri.withAppendedPath(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
            val bitmapLoad = GlideApp.with(pluginActivity)
                    .asBitmap()
                    .load(path)
                    .override(width, height)
                    .fitCenter()
                    .submit()
            val bitmap = bitmapLoad.get()
            val jpegBytes = ByteArrayOutputStream()
            jpegBytes.use {
                bitmap.compress(Bitmap.CompressFormat.JPEG, 70, jpegBytes)
                pluginActivity.runOnUiThread { result.success(jpegBytes.toByteArray()) }
            }
        }).start()
    }

    private fun initializeIfPermitted(context: Application) {
        permissionGranted = ContextCompat.checkSelfPermission(context,
                Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        if (!permissionGranted) {
            ActivityCompat.requestPermissions(pluginActivity,
                    arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), imagePermissionCode)
        } else {
            completeInitialize()
        }
    }

    private fun completeInitialize() {

//        if ( permissionGranted ) {
//        }

        initializedSuccessfully = permissionGranted
        activeResult?.success(permissionGranted)
        activeResult = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>?,
                                            grantResults: IntArray?): Boolean {
        when (requestCode) {
            imagePermissionCode -> {
                if (null != grantResults) {
                    permissionGranted = grantResults.isNotEmpty() &&
                            grantResults.get(0) == PackageManager.PERMISSION_GRANTED
                }
                completeInitialize()
            }
        }
        return true
    }
}
