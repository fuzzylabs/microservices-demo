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
using Google.Protobuf;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace cartservice.cartstore
{
    public class SlackMessage
    {
        public string channel { get; set; }
        public string text { get; set; }
    }

    public class RedisCartStore : ICartStore
    {
        private readonly IDistributedCache _cache;

        public RedisCartStore(IDistributedCache cache)
        {
            _cache = cache;
        }

        private static readonly HttpClient httpClient = new HttpClient();
        
        private async Task NotifySlackAsync(string productId)
        {
            var slackToken = Environment.GetEnvironmentVariable("SLACK_BOT_TOKEN");

            if (string.IsNullOrWhiteSpace(slackToken))
            {
                Console.WriteLine("SLACK_BOT_TOKEN is not set in environment variables.");
                return;
            }

            // Ensure we always have the correct auth header
            httpClient.DefaultRequestHeaders.Remove("Authorization");
            httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", slackToken);

            var message = $"🚨 I have detected a 'CRITICAL' error within the cartservice when someone tried to add (productId: `{productId}`). Let me see what I can do. 👀";

            // Manually construct JSON to avoid reflection-based serialization
            var json = $"{{\"channel\":\"C08M5SMJ0KW\",\"text\":\"{message.Replace("\"", "\\\"")}\"}}";
            var content = new StringContent(json, System.Text.Encoding.UTF8, "application/json");

            var response = await httpClient.PostAsync("https://slack.com/api/chat.postMessage", content);
            var responseBody = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                Console.WriteLine($"Slack API request failed: {response.StatusCode}");
            }
        }

        private async Task CallExternalApiAsync()
        {
            var request = new HttpRequestMessage
            {
                Method = HttpMethod.Post,
                RequestUri = new Uri("http://aa9781ba0ef2a41e68cdc7c3e7e6bb0e-1567177087.eu-west-2.elb.amazonaws.com/diagnose")
            };

            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", "password123");

            var response = await httpClient.SendAsync(request);

            var responseBody = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                Console.WriteLine($"External API call failed: {response.StatusCode}, Body: {responseBody}");
            }
            else
            {
                Console.WriteLine($"External API call succeeded: {responseBody}");
            }
        }

        public async Task AddItemAsync(string userId, string productId, int quantity)
        {
            Console.WriteLine($"AddItemAsync called with userId={userId}, productId={productId}, quantity={quantity}");

            if (productId == "AAAAAAAAA4")
            {
                await NotifySlackAsync(productId);
                CallExternalApiAsync();

                throw new Exception("Uh-oh, you tried to buy loafers");
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
                throw new RpcException(new Status(StatusCode.FailedPrecondition, $"Can't access cart storage. {ex}"));
            }
        }

        public async Task EmptyCartAsync(string userId)
        {
            Console.WriteLine($"EmptyCartAsync called with userId={userId}");

            try
            {
                var cart = new Hipstershop.Cart();
                await _cache.SetAsync(userId, cart.ToByteArray());
            }
            catch (Exception ex)
            {
                throw new RpcException(new Status(StatusCode.FailedPrecondition, $"Can't access cart storage. {ex}"));
            }
        }

        public async Task<Hipstershop.Cart> GetCartAsync(string userId)
        {
            Console.WriteLine($"GetCartAsync called with userId={userId}");

            try
            {
                // Access the cart from the cache
                var value = await _cache.GetAsync(userId);

                if (value != null)
                {
                    return Hipstershop.Cart.Parser.ParseFrom(value);
                }

                // We decided to return empty cart in cases when user wasn't in the cache before
                return new Hipstershop.Cart();
            }
            catch (Exception ex)
            {
                throw new RpcException(new Status(StatusCode.FailedPrecondition, $"Can't access cart storage. {ex}"));
            }
        }

        public bool Ping()
        {
            try
            {
                return true;
            }
            catch (Exception)
            {
                return false;
            }
        }
    }
}
