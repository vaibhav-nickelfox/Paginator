//
//  PaginationManager.swift
//  Paginator
//
//  Created by Vaibhav Parmar on 05/09/17.
//  Copyright © 2017 Vaibhav Parmar. All rights reserved.
//

import UIKit
import SSPullToRefresh

public protocol PaginationManagerDelegate {
	func refreshAll(completion: @escaping (_ hasMoreData: Bool) -> Void)
	func loadMore(completion: @escaping (_ hasMoreData: Bool) -> Void)
}

public enum PullToRefreshType {
	case none
	case basic
	case custom(PullToRefreshContentView)
}

public class PaginationManager: NSObject {
	fileprivate weak var scrollView: UIScrollView?
	fileprivate var refreshControl: UIRefreshControl?
	fileprivate var bottomLoader: UIView?
	fileprivate var isObservingKeyPath: Bool = false
	fileprivate var pullToRefreshView: PullToRefreshView?
	
	public var delegate: PaginationManagerDelegate?
	
	fileprivate var pullToRefreshType: PullToRefreshType {
		didSet {
			self.setupPullToRefresh()
		}
	}
	fileprivate var pullToRefreshContentView: UIView? = nil
	
	var isLoading = false
	var hasMoreDataToLoad = true
	
	public init(scrollView: UIScrollView, pullToRefreshType: PullToRefreshType = .basic) {
		self.scrollView = scrollView
		self.pullToRefreshType = pullToRefreshType
		super.init()
		self.setupPullToRefresh()
	}
	
	deinit {
		self.removeScrollViewOffsetObserver()
	}
	
	public func load(completion: @escaping () -> Void) {
		self.refresh {
			completion()
		}
	}
}

extension PaginationManager {
	
	func setupPullToRefresh() {
		switch self.pullToRefreshType {
		case .none:
			self.removeRefreshControl()
			self.removeCustomPullToRefreshView()
		case .basic:
			self.removeCustomPullToRefreshView()
			self.addRefreshControl()
		case .custom(let view):
			self.removeRefreshControl()
			self.addCustomPullToRefreshView(view)
		}
	}
	
	fileprivate func addRefreshControl() {
		self.refreshControl = UIRefreshControl()
		self.scrollView?.addSubview(self.refreshControl!)
		self.refreshControl?.addTarget(
			self,
			action: #selector(PaginationManager.handleRefresh),
			for: .valueChanged)
	}
	
	fileprivate func addCustomPullToRefreshView(_ contentView: PullToRefreshContentView) {
		guard  let scrollView = self.scrollView  else { return }
		self.pullToRefreshView = PullToRefreshView(scrollView: scrollView, delegate: self)
		self.pullToRefreshView?.contentView = contentView
	}
	
	fileprivate func removeRefreshControl() {
		self.refreshControl?.removeTarget(
			self,
			action: #selector(PaginationManager.handleRefresh),
			for: .valueChanged)
		self.refreshControl?.removeFromSuperview()
		self.refreshControl = nil
	}
	
	fileprivate func removeCustomPullToRefreshView() {
		self.pullToRefreshView = nil
	}
	
	@objc fileprivate func handleRefresh() {
		if self.isLoading {
			self.refreshControl?.endRefreshing()
			self.pullToRefreshView?.finishLoading()
			return
		}
		
		self.isLoading = true
		self.delegate?.refreshAll(completion: { [weak self] hasMoreData in
			guard let this = self else { return }
			this.isLoading = false
			this.hasMoreDataToLoad = hasMoreData
			if let refreshControl = this.refreshControl {
				refreshControl.endRefreshing()
			} else if let pullToRefreshView = this.pullToRefreshView {
				pullToRefreshView.finishLoading()
			}
		})
	}
	
	fileprivate func refresh(completion: @escaping () -> Void) {
		if self.isLoading {
			self.refreshControl?.endRefreshing()
			self.pullToRefreshView?.finishLoading()
			return
		}
		self.isLoading = true
		self.delegate?.refreshAll(completion: { [weak self] hasMoreData in
			guard let this = self else { return }
			this.isLoading = false
			this.hasMoreDataToLoad = hasMoreData
			if hasMoreData {
				this.addScrollViewOffsetObserver()
				this.addBottomLoader()
			}
			this.refreshControl?.endRefreshing()
			completion()
		})
	}
}

extension PaginationManager {
	fileprivate func addBottomLoader() {
		guard let scrollView = self.scrollView else { return }
		let view = UIView()
		view.frame.size = CGSize(width: scrollView.frame.width, height: 60)
		view.frame.origin = CGPoint(x: 0, y: scrollView.contentSize.height)
		view.backgroundColor = UIColor.clear
		let activity = UIActivityIndicatorView(activityIndicatorStyle: .gray)
		activity.frame = view.bounds
		activity.startAnimating()
		view.addSubview(activity)
		self.bottomLoader = view
		scrollView.contentInset.bottom = view.frame.height
	}
	
	fileprivate func showBottomLoader() {
		guard let scrollView = self.scrollView, let loader = self.bottomLoader else { return }
		scrollView.addSubview(loader)
	}
	
	fileprivate func hideBottomLoader() {
		self.bottomLoader?.removeFromSuperview()
	}
	
	fileprivate func removeBottomLoader() {
		self.bottomLoader?.removeFromSuperview()
		self.scrollView?.contentInset.bottom = 0
	}
	
	func addScrollViewOffsetObserver() {
		if self.isObservingKeyPath { return }
		self.scrollView?.addObserver(
			self,
			forKeyPath: "contentOffset",
			options: [.new],
			context: nil)
		self.isObservingKeyPath = true
	}
	
	func removeScrollViewOffsetObserver() {
		if self.isObservingKeyPath {
			self.scrollView?.removeObserver(self, forKeyPath: "contentOffset")
		}
		self.isObservingKeyPath = false
	}
	
	override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		guard let object = object as? UIScrollView, let keyPath = keyPath, let newValue = change?[.newKey] as? CGPoint else { return }
		if object == self.scrollView && keyPath == "contentOffset" {
			self.setContentOffSet(newValue)
		}
	}
	
	fileprivate func setContentOffSet(_ offset: CGPoint) {
		guard let scrollView = self.scrollView else { return }
		self.bottomLoader?.frame.origin.y = scrollView.contentSize.height
		if !scrollView.isDragging && !scrollView.isDecelerating  { return }
		if self.isLoading || !self.hasMoreDataToLoad { return }
		let offsetY = offset.y
		if offsetY >= scrollView.contentSize.height - scrollView.frame.size.height {
			self.isLoading = true
			self.showBottomLoader()
			self.delegate?.loadMore(completion: { [weak self] hasMoreData in
				guard let this = self else { return }
				this.hideBottomLoader()
				this.isLoading = false
				this.hasMoreDataToLoad = hasMoreData
				if !hasMoreData {
					this.removeBottomLoader()
					this.removeScrollViewOffsetObserver()
				}
			})
		}
	}
}

extension PaginationManager: PullToRefreshViewDelegate {
	public func pull(toRefreshViewDidStartLoading view: PullToRefreshView!) {
		self.handleRefresh()
	}
	
	public func pull(toRefreshViewDidFinishLoading view: PullToRefreshView!) {
		self.pullToRefreshView?.finishLoading()
	}
}
