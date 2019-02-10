// The MIT License (MIT)
//
// Copyright (c) 2015 Joakim Gyllström
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import UIKit
import Photos
import BSGridCollectionViewLayout
import SnapKit

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


final class PhotosViewController: UIViewController {
    @IBOutlet var collectionView: UICollectionView!

    @IBOutlet var navbar: UIView!
    @IBOutlet var toolbar: UIView!
    @IBOutlet var albumsButton: UIButton!
    @IBOutlet weak var doneButton: UIButton!
    @IBOutlet weak var clearButton: UIButton!
    @IBOutlet weak var librarySwitchContainer: UIView!

    var librarySwitch: CameraLibrarySwitch! {
        didSet {
            if !librarySwitch.allTargets.contains(self) {
                librarySwitch.addTarget(self, action: #selector(handleLibrarySwitchTap(sender:)), for: .valueChanged)
            }
        }
    }

    var photosDataSource: PhotoCollectionViewDataSource?
    var albumsDataSource: AlbumTableViewDataSource?
    fileprivate var composedDataSource: ComposedCollectionViewDataSource?
    
    fileprivate var defaultSelections: PHFetchResult<PHAsset>?
    
    fileprivate lazy var previewViewContoller: PreviewViewController? = {
        return PreviewViewController(nibName: nil, bundle: nil)
    }()

    fileprivate lazy var settings: BSImagePickerSettings = {
        let settings = Settings()
        settings.cellsPerRow = { _, _ in 3 }
        settings.takePhotos = false
        return settings
    }()

    override func awakeFromNib() {
        super.awakeFromNib()

        let fetchResults: [PHFetchResult] = { () -> [PHFetchResult<PHAssetCollection>] in
            let fetchOptions = PHFetchOptions()

            // Camera roll fetch result
            let cameraRollResult = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: fetchOptions)

            // Albums fetch result
            let albumResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

            return [cameraRollResult, albumResult]
        }()

        albumsDataSource = AlbumTableViewDataSource(fetchResults: fetchResults)
        
        PHPhotoLibrary.shared().register(self)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    override func loadView() {
        super.loadView()
        
        // Setup collection view
        collectionView.collectionViewLayout = GridCollectionViewLayout()
        collectionView.allowsMultipleSelection = true

        if let album = albumsDataSource?.fetchResults.first?.firstObject {
            initializePhotosDataSource(album, selections: defaultSelections)
            updateAlbumTitle(album)
            collectionView?.reloadData()
        }
        
        // Register cells
        photosDataSource?.registerCellIdentifiersForCollectionView(collectionView)

        setupDimmableNotifications()
    }

    override func viewDidAppear(_ animated: Bool) {
        librarySwitch.snp.makeConstraints { $0.edges.equalTo(0) }
        librarySwitch.labelsContainer.snp.makeConstraints { $0.edges.equalTo(0) }
    }

    @objc func handleLibrarySwitchTap(sender: CameraLibrarySwitch) {
        if sender.selectedIndex == 1 {
            self.performSegue(withIdentifier: "showCamera", sender: nil)
        }
    }

    @IBAction func doneButtonPressed(_ sender: UIButton) {
        if let assets = self.photosDataSource?.selections {
            let capture = Capture.current()
            DispatchQueue.global(qos: .userInitiated).async {
                let burst = Burst(assets: assets, orientation: self.orientation, url: capture.localDirURL)
                burst.process()
                capture.bursts.insert(burst)
            }
        }
        self.performSegue(withIdentifier: "showCamera", sender: nil)
    }

    @IBAction func clearButtonPressed(_ sender: UIButton) {
        self.photosDataSource?.selections = []
        self.collectionView.reloadData()
    }
    
    // MARK: Private helper methods
    @objc func updateAlbumTitle(_ album: PHAssetCollection) {
        guard let title = album.localizedTitle else { return }
        // Update album title
        albumsButton.setTitle(title, for: .normal)
    }
    
  @objc func initializePhotosDataSource(_ album: PHAssetCollection, selections: PHFetchResult<PHAsset>? = nil) {
        // Set up a photo data source with album
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        initializePhotosDataSourceWithFetchResult(PHAsset.fetchAssets(in: album, options: fetchOptions), selections: selections)
    }
    
    @objc func initializePhotosDataSourceWithFetchResult(_ fetchResult: PHFetchResult<PHAsset>, selections: PHFetchResult<PHAsset>? = nil) {
        let newDataSource = PhotoCollectionViewDataSource(fetchResult: fetchResult, selections: selections, settings: settings)
        
        // Transfer image size
        // TODO: Move image size to settings
        if let photosDataSource = photosDataSource {
            newDataSource.imageSize = photosDataSource.imageSize
            newDataSource.selections = photosDataSource.selections
        }
        
        photosDataSource = newDataSource
        
        // Hook up data source
        composedDataSource = ComposedCollectionViewDataSource(dataSources: [newDataSource])
        collectionView?.dataSource = composedDataSource
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let dest = segue.destination as? UINavigationController, let album = dest.viewControllers.first as? AlbumsViewController {
            album.delegate = self
            album.tableView.dataSource = albumsDataSource
            album.tableView.reloadData()
        }
    }
}

// MARK: UICollectionViewDelegate
extension PhotosViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        // NOTE: ALWAYS return false. We don't want the collectionView to be the source of thruth regarding selections
        // We can manage it ourself.
        // Make sure we have a data source and that we can make selections
        guard let photosDataSource = photosDataSource, collectionView.isUserInteractionEnabled else { return false }

        // We need a cell
        guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoCell else { return false }
        let asset = photosDataSource.fetchResult.object(at: indexPath.row)

        // Select or deselect?
        if let index = photosDataSource.selections.index(of: asset) { // Deselect
            // Deselect asset
            photosDataSource.selections.remove(at: index)

            // Get indexPaths of selected items
            let selectedIndexPaths = photosDataSource.selections.compactMap({ (asset) -> IndexPath? in
                let index = photosDataSource.fetchResult.index(of: asset)
                guard index != NSNotFound else { return nil }
                return IndexPath(item: index, section: 0)
            })

            // Reload selected cells to update their selection number
            UIView.setAnimationsEnabled(false)
            collectionView.reloadItems(at: selectedIndexPaths)
            UIView.setAnimationsEnabled(true)

            cell.photoSelected = false
        } else if photosDataSource.selections.count < settings.maxNumberOfSelections { // Select
            // Select asset if not already selected
            photosDataSource.selections.append(asset)

            // Set selection number
            if let selectionCharacter = settings.selectionCharacter {
                cell.selectionString = String(selectionCharacter)
            } else {
                cell.selectionString = String(photosDataSource.selections.count)
            }

            cell.photoSelected = true
        }

        return false
    }
}

// MARK: Traits
extension PhotosViewController {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if let collectionViewFlowLayout = collectionView.collectionViewLayout as? GridCollectionViewLayout {
            let itemSpacing: CGFloat = 6.0
            let cellsPerRow = settings.cellsPerRow(traitCollection.verticalSizeClass, traitCollection.horizontalSizeClass)
            
            collectionViewFlowLayout.itemSpacing = itemSpacing
            collectionViewFlowLayout.itemsPerRow = cellsPerRow
            
            photosDataSource?.imageSize = collectionViewFlowLayout.itemSize
        }
    }
}

extension PhotosViewController: AlbumsViewControllerDelegate {
    func selectedAlbum(at index: IndexPath) {
        // Update photos data source
        guard let album = albumsDataSource?.fetchResults[index.section][index.row] else { return }
        initializePhotosDataSource(album)
        updateAlbumTitle(album)
        collectionView?.reloadData()
    }
}

// MARK: UIImagePickerControllerDelegate
extension PhotosViewController: UIImagePickerControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
// Local variable inserted by Swift 4.2 migrator.
let info = convertFromUIImagePickerControllerInfoKeyDictionary(info)

        guard let image = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage else {
            picker.dismiss(animated: true, completion: nil)
            return
        }
        
        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            placeholder = request.placeholderForCreatedAsset
            }, completionHandler: { success, error in
                guard let placeholder = placeholder, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [placeholder.localIdentifier], options: nil).firstObject, success == true else {
                    picker.dismiss(animated: true, completion: nil)
                    return
                }
                
                DispatchQueue.main.async {
                    // TODO: move to a function. this is duplicated in didSelect
                    self.photosDataSource?.selections.append(asset)
                    
                    picker.dismiss(animated: true, completion: nil)
                }
        })
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}

// MARK: PHPhotoLibraryChangeObserver
extension PhotosViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let photosDataSource = photosDataSource, let collectionView = collectionView else {
            return
        }
        
        DispatchQueue.main.async(execute: { () -> Void in
            if let photosChanges = changeInstance.changeDetails(for: photosDataSource.fetchResult as! PHFetchResult<PHObject>) {
                // Update collection view
                // Alright...we get spammed with change notifications, even when there are none. So guard against it
                if photosChanges.hasIncrementalChanges && (photosChanges.removedIndexes?.count > 0 || photosChanges.insertedIndexes?.count > 0 || photosChanges.changedIndexes?.count > 0) {
                    // Update fetch result
                    photosDataSource.fetchResult = photosChanges.fetchResultAfterChanges as! PHFetchResult<PHAsset>
                    
                    collectionView.performBatchUpdates({
                        if let removed = photosChanges.removedIndexes {
                            collectionView.deleteItems(at: removed.bs_indexPathsForSection(1))
                        }
                        
                        if let inserted = photosChanges.insertedIndexes {
                            collectionView.insertItems(at: inserted.bs_indexPathsForSection(1))
                        }
                        
                        if let changed = photosChanges.changedIndexes {
                            collectionView.reloadItems(at: changed.bs_indexPathsForSection(1))
                        }
                    })
                    
                    // Changes is causing issues right now...fix me later
                    // Example of issue:
                    // 1. Take a new photo
                    // 2. We will get a change telling to insert that asset
                    // 3. While it's being inserted we get a bunch of change request for that same asset
                    // 4. It flickers when reloading it while being inserted
                    // TODO: FIX
                    //                    if let changed = photosChanges.changedIndexes {
                    //                        print("changed")
                    //                        collectionView.reloadItemsAtIndexPaths(changed.bs_indexPathsForSection(1))
                    //                    }
                } else if photosChanges.hasIncrementalChanges == false {
                    // Update fetch result
                    photosDataSource.fetchResult = photosChanges.fetchResultAfterChanges as! PHFetchResult<PHAsset>
                    
                    // Reload view
                    collectionView.reloadData()
                }
            }
        })
        
        
        // TODO: Changes in albums
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKeyDictionary(_ input: [UIImagePickerController.InfoKey: Any]) -> [String: Any] {
	return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
	return input.rawValue
}

extension PhotosViewController: Rotatable {
    var rotatableItems: [UIView] {
        return []
    }
}

extension PhotosViewController: Dimmable {

    func setMode(dark: Bool) {
        [self.view, navbar, toolbar].forEach { view in
            view.backgroundColor = dark ? ConstColor.defaultBackgroundDark.color() : ConstColor.defaultBackground.color()
        }
    }

}
