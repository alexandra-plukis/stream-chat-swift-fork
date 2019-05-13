//
//  ChatEndpoint.swift
//  GetStreamChat
//
//  Created by Alexey Bukhtin on 01/04/2019.
//  Copyright © 2019 Stream.io Inc. All rights reserved.
//

import Foundation

enum ChatEndpoint: EndpointProtocol {
    case query(Query)
    case sendMessage(Message, Channel)
    case sendMessageAction(MessageAction)
    case addReaction(_ reactionType: String, Message)
    case deleteReaction(_ reactionType: String, Message)
    case sendEvent(EventType, Channel)
}

extension ChatEndpoint {
    var method: Client.Method {
        if case .deleteReaction = self {
            return .delete
        }
        
        return .post
    }
    
    var path: String {
        switch self {
        case .query(let query):
            return path(with: query.channel).appending("query")
        case .sendMessage(_, let channel):
            return path(with: channel).appending("message")
        case .sendMessageAction(let messageAction):
            return path(with: messageAction.message).appending("action")
        case .addReaction(_, let message):
            return path(with: message).appending("reaction")
        case .deleteReaction(let reactionType, let message):
            return path(with: message).appending("reaction/\(reactionType)")
        case .sendEvent(_, let channel):
            return path(with: channel).appending("event")
        }
    }
    
    var body: Encodable? {
        switch self {
        case .query(let query):
            return query
        case .sendMessage(let message, _):
            return ["message": message]
        case .sendMessageAction(let messageAction):
            return messageAction
        case .addReaction(let reactionType, _):
            return ["reaction": ReactionRequestBody(type: reactionType, user: Client.shared.user)]
        case .deleteReaction:
            return nil
        case .sendEvent(let event, _):
            return ["event": ["type": event]]
        }
    }
    
    func path(with channel: Channel) -> String {
        return "channels/\(channel.type.rawValue)/\(channel.id)/"
    }
    
    func path(with message: Message) -> String {
        return "messages/\(message.id)/"
    }
}

private struct ReactionRequestBody: Encodable {
    let type: String
    let user: User?
}
