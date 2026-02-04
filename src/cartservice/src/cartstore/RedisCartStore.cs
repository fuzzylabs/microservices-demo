// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

using System;
using System.Linq;
using System.Threading.Tasks;
using Grpc.Core;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Logging;
using Google.Protobuf;

namespace cartservice.cartstore
{
    public class RedisCartStore : ICartStore
    {
        private readonly IDistributedCache _cache;
        private readonly ILogger<RedisCartStore> _logger;

        public RedisCartStore(IDistributedCache cache, ILogger<RedisCartStore> logger)
        {
            _cache = cache;
            _logger = logger;
        }

        private string EscapeJson(string s)
        {
            if (s == null) return "null";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n").Replace("\r", "\\r");
        }

        private void LogError(string message, Exception ex = null, string userId = null, string productId = null, int? quantity = null)
        {
            var timestamp = DateTime.UtcNow.ToString("o");
            var exMessage = ex != null ? EscapeJson(ex.Message) : "";
            var fullMessage = ex != null ? $"{message}: {exMessage}" : message;
            
            var json = $"{{\"severity\":\"error\",\"message\":\"{EscapeJson(fullMessage)}\",\"service\":\"cartservice\"";
            if (userId != null) json += $",\"userId\":\"{EscapeJson(userId)}\"";
            if (productId != null) json += $",\"productId\":\"{EscapeJson(productId)}\"";
            if (quantity != null) json += $",\"quantity\":{quantity}";
            if (ex != null) json += $",\"exception\":\"{EscapeJson(ex.ToString())}\"";
            json += $",\"timestamp\":\"{timestamp}\"}}";
            
            Console.WriteLine(json);
        }

        private void LogInfo(string message, string userId = null, string productId = null, int? quantity = null)
        {
            var timestamp = DateTime.UtcNow.ToString("o");
            
            var json = $"{{\"severity\":\"info\",\"message\":\"{EscapeJson(message)}\",\"service\":\"cartservice\"";
            if (userId != null) json += $",\"userId\":\"{EscapeJson(userId)}\"";
            if (productId != null) json += $",\"productId\":\"{EscapeJson(productId)}\"";
            if (quantity != null) json += $",\"quantity\":{quantity}";
            json += $",\"timestamp\":\"{timestamp}\"}}";
            
            Console.WriteLine(json);
        }

        public async Task AddItemAsync(string userId, string productId, int quantity)
        {
            LogInfo("AddItemAsync called", userId, productId, quantity);

            if (productId == "AAAAAAAAA4")
            {
                var error = new Exception("Uh-oh, you tried to buy loafers");
                LogError("Cart operation failed", error, userId, productId, quantity);
                throw error;
            }

            try
            {
                Hipstershop.Cart cart;
                var value = await _cache.GetAsync(userId);
                if (value == null)
                {
                    cart = new Hipstershop.Cart();
                    cart.UserId = userId;
                    cart.Items.Add(new Hipstershop.CartItem { ProductId = productId, Quantity = quantity });
                }
                else
                {
                    cart = Hipstershop.Cart.Parser.ParseFrom(value);
                    var existingItem = cart.Items.SingleOrDefault(i => i.ProductId == productId);
                    if (existingItem == null)
                    {
                        cart.Items.Add(new Hipstershop.CartItem { ProductId = productId, Quantity = quantity });
                    }
                    else
                    {
                        existingItem.Quantity += quantity;
                    }
                }
                await _cache.SetAsync(userId, cart.ToByteArray());
            }
            catch (Exception ex)
            {
                LogError("Can't access cart storage", ex, userId, productId, quantity);
                throw new RpcException(new Status(StatusCode.FailedPrecondition, $"Can't access cart storage. {ex}"));
            }
        }

        public async Task EmptyCartAsync(string userId)
        {
            LogInfo("EmptyCartAsync called", userId);

            try
            {
                var cart = new Hipstershop.Cart();
                await _cache.SetAsync(userId, cart.ToByteArray());
            }
            catch (Exception ex)
            {
                LogError("Can't access cart storage", ex, userId);
                throw new RpcException(new Status(StatusCode.FailedPrecondition, $"Can't access cart storage. {ex}"));
            }
        }

        public async Task<Hipstershop.Cart> GetCartAsync(string userId)
        {
            LogInfo("GetCartAsync called", userId);

            try
            {
                var value = await _cache.GetAsync(userId);

                if (value != null)
                {
                    return Hipstershop.Cart.Parser.ParseFrom(value);
                }

                return new Hipstershop.Cart();
            }
            catch (Exception ex)
            {
                LogError("Can't access cart storage", ex, userId);
                throw new RpcException(new Status(StatusCode.FailedPrecondition, $"Can't access cart storage. {ex}"));
            }
        }

        public bool Ping()
        {
            return true;
        }
    }
}
