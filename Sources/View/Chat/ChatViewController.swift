//
//  ChatViewController.swift
//  GetStreamChat
//
//  Created by Alexey Bukhtin on 03/04/2019.
//  Copyright © 2019 Stream.io Inc. All rights reserved.
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa
import RxKeyboard
import Nuke

public final class ChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    public var style = ChatViewStyle()
    private let disposeBag = DisposeBag()
    
    public private(set) lazy var composerView: ComposerView = {
        let composerView = ComposerView(frame: .zero)
        composerView.style = style.composer
        return composerView
    }()
    
    public private(set) lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.keyboardDismissMode = .interactive
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerMessageCell(style: style.incomingMessage)
        tableView.registerMessageCell(style: style.outgoingMessage)
        tableView.register(cellType: StatusTableViewCell.self)
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: CGFloat.messagesBottomMargin, right: 0)
        view.insertSubview(tableView, at: 0)
        return tableView
    }()
    
    public var channelPresenter: ChannelPresenter? {
        didSet {
            if let channelPresenter = channelPresenter {
                Driver.merge(channelPresenter.changes,
                             channelPresenter.loading)
                    .drive(onNext: { [weak self] in self?.updateTableView(with: $0) })
                    .disposed(by: disposeBag)
            }
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupComposerView()
        setupTableView()
        channelPresenter?.load()
    }
    
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return style.backgroundColor.isDark ? .lightContent : .default
    }
}

// MARK: - Composer

extension ChatViewController {
    
    private func setupComposerView() {
        composerView.addToSuperview(view)
        
        composerView.sendButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.send() })
            .disposed(by: disposeBag)
        
        RxKeyboard.instance.visibleHeight
            .drive(onNext: { [weak self] height in
                let bottom: CGFloat = height + .messagesBottomMargin + (height > 0 ? 0 : .safeAreaBottom)
                self?.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
            })
            .disposed(by: disposeBag)
        
        RxKeyboard.instance.willShowVisibleHeight
            .drive(onNext: { [weak self] height in
                if let self = self {
                    var contentOffset = self.tableView.contentOffset
                    contentOffset.y += height - .safeAreaBottom
                    self.tableView.contentOffset = contentOffset
                }
            })
            .disposed(by: disposeBag)
    }
    
    private func send() {
        let text = composerView.text
        composerView.reset()
        channelPresenter?.send(text: text)
    }
}

// MARK: - Table View

extension ChatViewController {
    
    private func setupTableView() {
        tableView.backgroundColor = style.backgroundColor
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }
    
    private func updateTableView(with changes: ChannelChanges) {
        if case let .updated(row, position, animated) = changes {
            tableView.reloadData()
            tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: position, animated: animated)
        }
        
        if case let .itemAdded(row, reloadRow, forceToScroll) = changes {
            let indexPath = IndexPath(row: row, section: 0)
            
            tableView.update {
                tableView.insertRows(at: [indexPath], with: .none)
                
                if let reloadRow = reloadRow {
                    tableView.reloadRows(at: [IndexPath(row: reloadRow, section: 0)], with: .none)
                }
            }
            
            if forceToScroll || tableView.bottomContentOffset < .messageAvatarSize {
                tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
            }
        }
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return channelPresenter?.items.count ?? 0
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let presenter = channelPresenter, indexPath.row < presenter.items.count else {
            return .unused
        }
        
        if case .loading = presenter.items[indexPath.row] {
            return loadingCell(at: indexPath)
        }
        
        if case let .status(title, subtitle) = presenter.items[indexPath.row] {
            return statusCell(at: indexPath, title: title, subtitle: subtitle)
        }
        
        if case .message(let message) = presenter.items[indexPath.row] {
            return messageCell(at: indexPath, message: message)
        }
        
        return .unused
    }
    
    private func loadingCell(at indexPath: IndexPath) -> UITableViewCell {
        channelPresenter?.loadNext()
        return statusCell(at: indexPath, title: "Loading...")
    }
    
    private func messageCell(at indexPath: IndexPath, message: Message) -> UITableViewCell {
        guard let presenter = channelPresenter else {
            return .unused
        }
        
        let isIncoming = message.user != Client.shared.user
        let cell = tableView.dequeueMessageCell(for: indexPath, style: isIncoming ? style.incomingMessage : style.outgoingMessage)
        cell.update(message: message.text)
        var showAvatar = true
        
        if indexPath.row < (presenter.items.count - 1), case .message(let nextMessage) = presenter.items[indexPath.row + 1] {
            showAvatar = nextMessage.user != message.user
            
            if !showAvatar {
                cell.paddingType = .small
            }
        }
        
        if indexPath.row > 0,
            case .message(let prevMessage) = presenter.items[indexPath.row - 1],
            prevMessage.user == message.user {
            cell.update(isContinueMessage: true)
        }
        
        if showAvatar {
            cell.update(name: message.user.name, date: message.created)
            cell.update(avatarURL: message.user.avatarURL, name: message.user.name)
        }
        
        if !message.attachments.isEmpty {
            cell.add(attachments: message.attachments, userName: message.user.name)
        }
        
        return cell
    }
    
    private func statusCell(at indexPath: IndexPath, title: String, subtitle: String? = nil) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(for: indexPath, cellType: StatusTableViewCell.self) as StatusTableViewCell
        cell.backgroundColor = style.backgroundColor
        cell.update(title: title, subtitle: subtitle)
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let cell = cell as? MessageTableViewCell {
            cell.free()
        }
    }
    
    public func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard  let presenter = channelPresenter,
            case .message(let message) = presenter.items[indexPath.row],
            !message.attachments.isEmpty else {
                return false
        }
        
        return true
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard  let presenter = channelPresenter,
            case .message(let message) = presenter.items[indexPath.row] else {
                return
        }
        
        if let first = message.attachments.first, !first.isImage {
            showWebView(url: first.url, title: first.title)
            return
        }
        
        showMediaGallery(with: message.attachments.compactMap { MediaGalleryItem(title: $0.title, url: $0.imageURL) })
    }
}
