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


final class PhotosViewController : UICollectionViewController {    
    @objc var selectionClosure: ((_ asset: PHAsset) -> Void)?
    @objc var deselectionClosure: ((_ asset: PHAsset) -> Void)?
    @objc var cancelClosure: ((_ assets: [PHAsset]) -> Void)?
    @objc var finishClosure: ((_ assets: [PHAsset]) -> Void)?
    @objc var selectLimitReachedClosure: ((_ selectionLimit: Int) -> Void)?
    
    @objc var doneBarButton: UIBarButtonItem?
    @objc var cancelBarButton: UIBarButtonItem?
    @objc var albumTitleView: UIButton?

    let navbar = UIView()
    let toolbar = UIView()

    var photosDataSource: PhotoCollectionViewDataSource?
    var albumsDataSource: AlbumTableViewDataSource
    fileprivate let cameraDataSource: CameraCollectionViewDataSource
    fileprivate var composedDataSource: ComposedCollectionViewDataSource?
    
    fileprivate var defaultSelections: PHFetchResult<PHAsset>?
    
    let settings: BSImagePickerSettings
    
    fileprivate let doneBarButtonTitle: String = NSLocalizedString("Done", comment: "Done")
    
    lazy var albumsViewControllers: (AlbumsViewController, UINavigationController) = {
        let storyboard = UIStoryboard(name: "Albums", bundle: BSImagePickerViewController.bundle)
        let nav = storyboard.instantiateInitialViewController() as! UINavigationController
        let vc = nav.viewControllers.first! as! AlbumsViewController
        vc.tableView.dataSource = self.albumsDataSource
        vc.tableView.delegate = self
        
        return (vc, nav)
    }()
    
    fileprivate lazy var previewViewContoller: PreviewViewController? = {
        return PreviewViewController(nibName: nil, bundle: nil)
    }()
    
    required init(fetchResults: [PHFetchResult<PHAssetCollection>], defaultSelections: PHFetchResult<PHAsset>? = nil, settings aSettings: BSImagePickerSettings) {
        albumsDataSource = AlbumTableViewDataSource(fetchResults: fetchResults)
        cameraDataSource = CameraCollectionViewDataSource(settings: aSettings, cameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera))
        self.defaultSelections = defaultSelections
        settings = aSettings
        
        super.init(collectionViewLayout: GridCollectionViewLayout())
        
        PHPhotoLibrary.shared().register(self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("b0rk: initWithCoder not implemented")
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    override func loadView() {
        super.loadView()
        
        // Setup collection view
        collectionView?.backgroundColor = settings.backgroundColor
        collectionView?.allowsMultipleSelection = true
        collectionView.contentInset = UIEdgeInsets(top: 50, left: 0, bottom: 0, right: 0)
        
        // Set an empty title to get < back button
        title = " "
        
        // Set button actions and add them to navigation item
        doneBarButton?.target = self
        doneBarButton?.action = #selector(PhotosViewController.doneButtonPressed(_:))
        cancelBarButton?.target = self
        cancelBarButton?.action = #selector(PhotosViewController.cancelButtonPressed(_:))
        albumTitleView?.addTarget(self, action: #selector(PhotosViewController.albumButtonPressed(_:)), for: .touchUpInside)
        navigationItem.leftBarButtonItem = cancelBarButton
        navigationItem.rightBarButtonItem = doneBarButton
        navigationItem.titleView = albumTitleView

        if let album = albumsDataSource.fetchResults.first?.firstObject {
            initializePhotosDataSource(album, selections: defaultSelections)
            updateAlbumTitle(album)
            collectionView?.reloadData()
        }
        
        // Register cells
        photosDataSource?.registerCellIdentifiersForCollectionView(collectionView)
        cameraDataSource.registerCellIdentifiersForCollectionView(collectionView)

        setupDimmableNotifications()
        setupButtons()
    }

    private func setupButtons() {
        self.view.addSubview(navbar)

        navbar.snp.makeConstraints { (make) in
            make.left.top.right.equalTo(0)
            make.height.equalTo(60)
        }

        let addButton = UIButton()
        addButton.setTitle(ConstString.libraryScreenAddButtonTitle.localized(), for: .normal)
        addButton.setTitleColor(.blue, for: .normal)
        self.view.addSubview(addButton)

        addButton.snp.makeConstraints { (make) in
            make.top.equalTo(0)
            make.right.equalTo(0)
            make.height.equalTo(50)
            make.width.equalTo(75)
        }

        addButton.addControlEvent(.touchUpInside) { [unowned self] in
            if let assets = self.photosDataSource?.selections {
                let capture = Capture.current()
                DispatchQueue.global(qos: .userInitiated).async {
                    let burst = Burst(assets: assets, orientation: self.orientation, url: capture.localDirURL)
                    burst.process()
                    capture.bursts.insert(burst)
                }
            }

            // TODO: scroll over to camera
        }

        self.view.addSubview(toolbar)

        toolbar.snp.makeConstraints { (make) in
            make.left.bottom.right.equalTo(0)
            make.height.equalTo(60)
        }

        let clearButton = UIButton()
        clearButton.setTitle(ConstString.libraryScreenClearButtonTitle.localized(), for: .normal)
        clearButton.setTitleColor(.blue, for: .normal)
        toolbar.addSubview(clearButton)

        clearButton.snp.makeConstraints { (make) in
            make.left.equalTo(0)
            make.height.equalTo(50)
            make.width.equalTo(75)
            make.centerY.equalToSuperview()
        }

        clearButton.addControlEvent(.touchUpInside) { [unowned self] in
            self.photosDataSource?.selections = []
            self.collectionView.reloadData()
        }

        let albumsButton = UIButton()
        albumsButton.setTitle("Albums ^", for: .normal)
        albumsButton.setTitleColor(.blue, for: .normal)
        toolbar.addSubview(albumsButton)

        albumsButton.snp.makeConstraints { (make) in
            make.width.equalTo(150)
            make.height.equalTo(50)
            make.centerX.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
        }

        albumsButton.addTarget(self, action: #selector(albumButtonPressed(_:)), for: .touchUpInside)

        let selectButton = UIButton()
        selectButton.setTitle(ConstString.libraryScreenSelectAllButtonTitle.localized(), for: .normal)
        selectButton.setTitleColor(.blue, for: .normal)
        toolbar.addSubview(selectButton)

        selectButton.addControlEvent(.touchUpInside) { [unowned self] in
            guard let source = self.photosDataSource else { return }

            // make sure current selections stay ahead of the order
            var selections: [PHAsset] = source.selections
            source.fetchResult.enumerateObjects({ asset, _, _ in
                if !selections.contains(asset) {
                    selections.append(asset)
                }
            })
            source.selections = selections
            self.collectionView.reloadData()
        }

        selectButton.snp.makeConstraints { (make) in
            make.right.equalTo(-16)
            make.height.equalTo(50)
            make.width.equalTo(75)
            make.centerY.equalToSuperview()
        }
    }
    
    // MARK: Appear/Disappear
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateDoneButton()
    }
    
    // MARK: Button actions
    @objc func cancelButtonPressed(_ sender: UIBarButtonItem) {
        guard let closure = cancelClosure, let photosDataSource = photosDataSource else {
            dismiss(animated: true, completion: nil)
            return
        }
        DispatchQueue.global().async {
            closure(photosDataSource.selections)
        }
        
        dismiss(animated: true, completion: nil)
    }
    
    @objc func doneButtonPressed(_ sender: UIBarButtonItem) {
        guard let closure = finishClosure, let photosDataSource = photosDataSource else {
            dismiss(animated: true, completion: nil)
            return
        }
        
        DispatchQueue.global().async {
            closure(photosDataSource.selections)
        }
        
        // TODO: scroll back over to camera view
    }
    
    @objc func albumButtonPressed(_ sender: UIButton) {
        albumsViewControllers.0.tableView.reloadData()
        
        present(albumsViewControllers.1, animated: true, completion: nil)
    }
    
    // MARK: Private helper methods
    @objc func updateDoneButton() {
        guard let photosDataSource = photosDataSource else { return }

        if photosDataSource.selections.count > 0 {
            doneBarButton = UIBarButtonItem(title: "\(doneBarButtonTitle) (\(photosDataSource.selections.count))", style: .done, target: doneBarButton?.target, action: doneBarButton?.action)
        } else {
            doneBarButton = UIBarButtonItem(title: doneBarButtonTitle, style: .done, target: doneBarButton?.target, action: doneBarButton?.action)
        }

        // Enabled?
        doneBarButton?.isEnabled = photosDataSource.selections.count > 0

        navigationItem.rightBarButtonItem = doneBarButton
    }

    @objc func updateAlbumTitle(_ album: PHAssetCollection) {
        guard let title = album.localizedTitle else { return }
        // Update album title
        albumTitleView?.setAlbumTitle(title)
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
        composedDataSource = ComposedCollectionViewDataSource(dataSources: [cameraDataSource, newDataSource])
        collectionView?.dataSource = composedDataSource
        collectionView?.delegate = self
    }
}

// MARK: UICollectionViewDelegate
extension PhotosViewController {
    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        // NOTE: ALWAYS return false. We don't want the collectionView to be the source of thruth regarding selections
        // We can manage it ourself.

        // Camera shouldn't be selected, but pop the UIImagePickerController!
        if let composedDataSource = composedDataSource , composedDataSource.dataSources[indexPath.section].isEqual(cameraDataSource) {
            let cameraController = UIImagePickerController()
            cameraController.allowsEditing = false
            cameraController.sourceType = .camera
            
            self.present(cameraController, animated: true, completion: nil)
            
            return false
        }

        // Make sure we have a data source and that we can make selections
        guard let photosDataSource = photosDataSource, collectionView.isUserInteractionEnabled else { return false }

        // We need a cell
        guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoCell else { return false }
        let asset = photosDataSource.fetchResult.object(at: indexPath.row)

        // Select or deselect?
        if let index = photosDataSource.selections.index(of: asset) { // Deselect
            // Deselect asset
            photosDataSource.selections.remove(at: index)

            // Update done button
            updateDoneButton()

            // Get indexPaths of selected items
            let selectedIndexPaths = photosDataSource.selections.compactMap({ (asset) -> IndexPath? in
                let index = photosDataSource.fetchResult.index(of: asset)
                guard index != NSNotFound else { return nil }
                return IndexPath(item: index, section: 1)
            })

            // Reload selected cells to update their selection number
            UIView.setAnimationsEnabled(false)
            collectionView.reloadItems(at: selectedIndexPaths)
            UIView.setAnimationsEnabled(true)

            cell.photoSelected = false

            // Call deselection closure
            if let closure = deselectionClosure {
                DispatchQueue.global().async {
                    closure(asset)
                }
            }
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

            // Update done button
            updateDoneButton()

            // Call selection closure
            if let closure = selectionClosure {
                DispatchQueue.global().async {
                    closure(asset)
                }
            }
        } else if photosDataSource.selections.count >= settings.maxNumberOfSelections,
            let closure = selectLimitReachedClosure {
            DispatchQueue.global().async {
                closure(self.settings.maxNumberOfSelections)
            }
        }

        return false
    }
    
    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? CameraCell else {
            return
        }
        
        cell.startLiveBackground() // Start live background
    }
}

// MARK: UIPopoverPresentationControllerDelegate
extension PhotosViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
    
    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        return true
    }
}

// MARK: UITableViewDelegate
extension PhotosViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Update photos data source
        let album = albumsDataSource.fetchResults[indexPath.section][indexPath.row]
        initializePhotosDataSource(album)
        updateAlbumTitle(album)
        collectionView?.reloadData()
        
        // Dismiss album selection
        albumsViewControllers.0.dismiss(animated: true, completion: nil)
    }
}

// MARK: Traits
extension PhotosViewController {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if let collectionViewFlowLayout = collectionViewLayout as? GridCollectionViewLayout {
            let itemSpacing: CGFloat = 2.0
            let cellsPerRow = settings.cellsPerRow(traitCollection.verticalSizeClass, traitCollection.horizontalSizeClass)
            
            collectionViewFlowLayout.itemSpacing = itemSpacing
            collectionViewFlowLayout.itemsPerRow = cellsPerRow
            
            photosDataSource?.imageSize = collectionViewFlowLayout.itemSize
            
            updateDoneButton()
        }
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
                    self.updateDoneButton()
                    
                    // Call selection closure
                    if let closure = self.selectionClosure {
                        DispatchQueue.global().async {
                            closure(asset)
                        }
                    }
                    
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
        [self.collectionView, navbar, toolbar].forEach { view in
            view.backgroundColor = dark ? ConstColor.defaultBackgroundDark.color() : ConstColor.defaultBackground.color()
        }
    }

}
